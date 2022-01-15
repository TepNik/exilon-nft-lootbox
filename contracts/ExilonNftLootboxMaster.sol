// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.11;

import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "./pancake-swap/interfaces/IPancakeRouter02.sol";

import "./ExilonNftLootboxLibrary.sol";
import "./FeesCalculator.sol";
import "./interfaces/IExilonNftLootboxMain.sol";
import "./interfaces/IFundsHolderFactory.sol";
import "./interfaces/IFundsHolder.sol";
import "./interfaces/IExilonNftLootboxMaster.sol";

contract ExilonNftLootboxMaster is ERC1155Holder, FeesCalculator, IExilonNftLootboxMaster {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.UintSet;

    // Contract ERC1155 for creating lootboxes
    IExilonNftLootboxMain public immutable exilonNftLootboxMain;
    // Contract for creating funds holder contracts
    IFundsHolderFactory public immutable fundsHolderFactory;

    // Connects ids with the contract that holds the funds of this id
    mapping(uint256 => address) public idsToFundsHolders;
    // Connects ids with the creator address
    mapping(uint256 => address) public override idsToCreator;
    // Connects creator address with the ids, that he maded
    mapping(address => EnumerableSet.UintSet) private _creatorToIds;
    // Connects creator address and id of lootbox with amount of creator's winning places that users have already opened
    mapping(address => mapping(uint256 => uint256)) public numberOfCreatorsOpenedLootboxes;
    // Last id
    uint256 private _lastId;

    // Info abount prizes
    mapping(uint256 => ExilonNftLootboxLibrary.WinningPlace[]) private _prizes;
    // Connects id with the amount of an unpacked lootboxes
    mapping(uint256 => uint256) public lootxesAmount;

    // Amount in USD for creating lootbox
    uint256 public creatingPrice;
    // Minimal amount in USD for openning price
    uint256 public minimumOpeningPrice;
    // Connects id with it's openning price
    mapping(uint256 => uint256) public override defaultOpeningPrice;
    // Percentage from openning price that the creators will get (100% - 10_000)
    uint256 public creatorPercentage = 5_000; // 50%

    // Parameters for random
    uint256 public minRandomPercentage = 9_000; // 90%
    uint256 public maxRandomPercentage = 15_000; // 150%
    uint256 public powParameter = 5;
    uint256 private _nonce;

    // Parameters for opening price of mega lootboxes
    uint256 public maxOpeningPricePercentage = 20_000; // 200%
    uint256 public priceDeltaPercentage = 100; // 1%
    uint256 public priceTimeDelta = 5 minutes;

    struct LootboxPurchaseInfo {
        uint256 price;
        uint256 timestamp;
    }
    // Connects
    mapping(uint256 => LootboxPurchaseInfo) private _lastPurchase;

    // Amount of exilon tokens that the openers of lootboxes will get
    uint256 public amountOfAirdropTokenToOpenner;

    // Addresses info
    IERC20 public immutable exilon;
    IERC20 public airdropToken;

    // Connects an id and token address with the available amount of this token for this id
    mapping(uint256 => mapping(address => uint256)) private _totalSharesOfERC20;

    // Connects and id and winning place index with it's creator
    mapping(uint256 => mapping(uint256 => address)) private _winningPlaceCreator;

    modifier onlyLootboxMain() {
        require(msg.sender == address(exilonNftLootboxMain), "ExilonNftLootboxMaster: No access");
        _;
    }

    event LootboxMaded(address indexed maker, uint256 id, uint256 amount);
    event WithdrawLootbox(address indexed maker, uint256 id, uint256 amount);
    event IdDeleted(uint256 id, address indexed fundsHolder);
    event SuccessfullyWithdrawnTokens(
        address indexed user,
        ExilonNftLootboxLibrary.TokenInfo[] tokens,
        address[] creators
    );
    event TransferFeeToCreator(address indexed creator, uint256 bnbAmount);
    event MergeMaded(uint256 idFrom, uint256 idTo);

    event PriceChanges(
        uint256 newCreatingPrice,
        uint256 newMinimumOpeningPrice,
        uint256 newCreatorPercentage
    );
    event RandomParamsChange(
        uint256 newMinRandomPercentage,
        uint256 newMaxRandomPercentage,
        uint256 newPowParameter
    );
    event OpeningPriceForMegaLootboxesChange(
        uint256 newMaxOpeningPricePercentage,
        uint256 newPriceDeltaPercentage,
        uint256 newPriceTimeDelta
    );
    event OpeningPriceForIdChanged(uint256 id, uint256 newOpeningPrice);
    event ChangeAirdropParams(address airdropToken, uint256 airdropAmount);

    event BadAirdropTransfer(address indexed to, uint256 amount);

    constructor(
        IERC20 _exilon,
        IERC20 _airdropToken,
        address _usdToken,
        IPancakeRouter02 _pancakeRouter,
        address _feeReceiver,
        IAccess _accessControl,
        IExilonNftLootboxMain _exilonNftLootboxMain,
        IFundsHolderFactory _fundsHolderFactory
    ) FeesCalculator(_usdToken, _pancakeRouter, _feeReceiver, _accessControl) {
        exilon = _exilon;

        uint256 oneAirdropToken = 10**IERC20Metadata(address(_airdropToken)).decimals();
        amountOfAirdropTokenToOpenner = oneAirdropToken;
        airdropToken = _airdropToken;

        minimumOpeningPrice = _oneUsd;
        creatingPrice = _oneUsd;

        exilonNftLootboxMain = _exilonNftLootboxMain;
        _exilonNftLootboxMain.init();

        fundsHolderFactory = _fundsHolderFactory;
        _fundsHolderFactory.init();

        emit ChangeAirdropParams(address(_airdropToken), oneAirdropToken);
        emit PriceChanges(_oneUsd, _oneUsd, creatorPercentage);
        emit RandomParamsChange(minRandomPercentage, maxRandomPercentage, powParameter);
        emit OpeningPriceForMegaLootboxesChange(
            maxOpeningPricePercentage,
            priceDeltaPercentage,
            priceTimeDelta
        );
    }

    // max - 200 different tokens for all winning places
    function makeLootBox(
        ExilonNftLootboxLibrary.WinningPlace[] calldata winningPlaces,
        uint256 _openingPrice,
        bool onMarket,
        string memory _uri
    ) external payable nonReentrant onlyEOA {
        require(
            winningPlaces.length > 0,
            "ExilonNftLootboxMaster: Must be at least one winning place"
        );

        _checkFees(creatingPrice);
        _processFeeTransferOnFeeReceiver();

        // get total information about tokens in all winningPlaces
        (
            ExilonNftLootboxLibrary.TokenInfo[] memory allTokensInfo,
            uint256 amountOfLootBoxes
        ) = ExilonNftLootboxLibrary.processTokensInfo(winningPlaces);

        uint256 lastId = _lastId++;
        {
            address receiver;
            if (onMarket) {
                receiver = address(this);
            } else {
                receiver = msg.sender;
            }
            exilonNftLootboxMain.mint(receiver, lastId, amountOfLootBoxes, _uri);
        }

        lootxesAmount[lastId] = amountOfLootBoxes;

        require(
            _openingPrice >= minimumOpeningPrice,
            "ExilonNftLootboxMaster: Opening price is too low"
        );
        defaultOpeningPrice[lastId] = _openingPrice;

        idsToCreator[lastId] = msg.sender;
        _creatorToIds[msg.sender].add(lastId);

        address fundsHolder = fundsHolderFactory.deployNewContract();

        idsToFundsHolders[lastId] = fundsHolder;

        ExilonNftLootboxLibrary.transferFundsToFundsHolder(
            allTokensInfo,
            fundsHolder,
            lastId,
            address(exilon),
            _totalSharesOfERC20
        );

        for (uint256 i = 0; i < winningPlaces.length; ++i) {
            _prizes[lastId].push(winningPlaces[i]);
        }

        emit LootboxMaded(msg.sender, lastId, amountOfLootBoxes);
    }

    function withdrawPrize(uint256 id, uint256 amount) external payable nonReentrant onlyEOA {
        _withdrawPrize(msg.sender, id, amount);
    }

    function buyId(uint256 id, uint256 amount) external payable nonReentrant onlyEOA {
        require(
            exilonNftLootboxMain.balanceOf(address(this), id) >= amount,
            "ExilonNftLootboxMaster: Not enough ids on market"
        );
        _withdrawPrize(address(this), id, amount);
    }

    struct processMergeStack {
        ExilonNftLootboxLibrary.WinningPlace[] winningPlacesFrom;
        ExilonNftLootboxLibrary.TokenInfo[] allTokensInfoFrom;
        uint256 totalLootboxes;
        address fundsHolderFrom;
        address fundsHolderTo;
    }

    function processMerge(uint256 idFrom, uint256 idTo) external onlyLootboxMain nonReentrant {
        processMergeStack memory stack;

        stack.winningPlacesFrom = _prizes[idFrom];

        (stack.allTokensInfoFrom, stack.totalLootboxes) = ExilonNftLootboxLibrary.processTokensInfo(
            stack.winningPlacesFrom
        );

        stack.fundsHolderFrom = idsToFundsHolders[idFrom];
        stack.fundsHolderTo = idsToFundsHolders[idTo];
        for (uint256 i = 0; i < stack.allTokensInfoFrom.length; ++i) {
            uint256 balanceBefore;
            if (stack.allTokensInfoFrom[i].tokenType == ExilonNftLootboxLibrary.TokenType.ERC20) {
                balanceBefore = IERC20(stack.allTokensInfoFrom[i].tokenAddress).balanceOf(
                    stack.fundsHolderTo
                );
            }

            require(
                IFundsHolder(stack.fundsHolderFrom).withdrawToken(
                    stack.allTokensInfoFrom[i],
                    stack.fundsHolderTo
                ),
                "ExilonNftLootboxMaster: Merge transfer failed"
            );

            ExilonNftLootboxLibrary.processMergeInfo(
                ExilonNftLootboxLibrary.processMergeInfoInputStruct({
                    idFrom: idFrom,
                    idTo: idTo,
                    tokenAddress: stack.allTokensInfoFrom[i].tokenAddress,
                    tokenType: stack.allTokensInfoFrom[i].tokenType,
                    balanceBefore: balanceBefore,
                    fundsHolderTo: stack.fundsHolderTo,
                    processingTokenAddress: stack.allTokensInfoFrom[i].tokenAddress,
                    winningPlacesFrom: stack.winningPlacesFrom
                }),
                _totalSharesOfERC20,
                _prizes
            );
        }

        ExilonNftLootboxLibrary.mergeWinningPrizeInfo(
            idFrom,
            idTo,
            _prizes[idTo].length,
            stack.winningPlacesFrom.length,
            idsToCreator[idFrom],
            _prizes,
            _winningPlaceCreator
        );

        exilonNftLootboxMain.burn(address(this), idFrom, stack.totalLootboxes);

        _deleteId(idFrom, stack.fundsHolderFrom);

        emit MergeMaded(idFrom, idTo);
    }

    function setWinningPlacesToTheCreator(uint256 id)
        external
        override
        onlyLootboxMain
        nonReentrant
    {
        uint256 length = _prizes[id].length;
        address creator = idsToCreator[id];
        for (uint256 i = 0; i < length; ++i) {
            _winningPlaceCreator[id][i] = creator;
        }
    }

    function withdrawToken(IERC20 token, uint256 amount) external onlyAdmin nonReentrant {
        ExilonNftLootboxLibrary.sendTokenCarefully(token, amount, true);
    }

    function setPriceInfo(
        uint256 _creatingPrice,
        uint256 _minimumOpeningPrice,
        uint256 _creatorPercentage
    ) external onlyAdmin {
        require(_creatorPercentage <= 10_000, "ExilonNftLootboxMaster: Too big percentage");
        require(minimumOpeningPrice > 0, "ExilonNftLootboxMaster: Min price");

        creatingPrice = _creatingPrice;
        minimumOpeningPrice = _minimumOpeningPrice;
        creatorPercentage = _creatorPercentage;

        emit PriceChanges(_creatingPrice, _minimumOpeningPrice, _creatorPercentage);
    }

    function setRandomParams(
        uint256 _minRandomPercentage,
        uint256 _maxRandomPercentage,
        uint256 _powParameter
    ) external onlyAdmin {
        require(
            _minRandomPercentage <= _maxRandomPercentage &&
                _minRandomPercentage >= 5_000 &&
                _minRandomPercentage <= 10_000 &&
                _maxRandomPercentage >= 10_000 &&
                _maxRandomPercentage <= 100_000,
            "ExilonNftLootboxMaster: Wrong percentage"
        ); // 50% min and 1000% max
        require(
            _powParameter >= 1 && _powParameter <= 8,
            "ExilonNftLootboxMaster: Wrong pow parameter"
        );

        minRandomPercentage = _minRandomPercentage;
        maxRandomPercentage = _maxRandomPercentage;
        powParameter = _powParameter;

        emit RandomParamsChange(_minRandomPercentage, _maxRandomPercentage, _powParameter);
    }

    function setOpeningPriceForMegaLootboxes(
        uint256 newMaxOpeningPricePercentage,
        uint256 newPriceDeltaPercentage,
        uint256 newPriceTimeDelta
    ) external onlyAdmin {
        require(
            newMaxOpeningPricePercentage >= 10_000 && newMaxOpeningPricePercentage <= 100_000,
            "ExilonNftLootboxMaster: Wrong max"
        );
        require(newPriceDeltaPercentage <= 1_000, "ExilonNftLootboxMaster: Wrong price delta");
        require(newPriceTimeDelta <= 1 days, "ExilonNftLootboxMaster: Bad time delta");

        maxOpeningPricePercentage = newMaxOpeningPricePercentage;
        priceDeltaPercentage = newPriceDeltaPercentage;
        priceTimeDelta = newPriceTimeDelta;

        emit OpeningPriceForMegaLootboxesChange(
            newMaxOpeningPricePercentage,
            newPriceDeltaPercentage,
            newPriceTimeDelta
        );
    }

    function setOpeningPriceForId(uint256 id, uint256 newOpeningPrice) external {
        require(
            msg.sender == idsToCreator[id] || accessControl.hasRole(bytes32(0), msg.sender),
            "ExilonNftLootboxMaster: No access"
        );
        require(lootxesAmount[id] > 0, "ExilonNftLootboxMaster: No such id");
        require(
            exilonNftLootboxMain.lootboxType(id) !=
                ExilonNftLootboxLibrary.LootBoxType.MEGA_LOOTBOX_RESERVE,
            "ExilonNftLootboxMaster: No refund box"
        );

        defaultOpeningPrice[id] = newOpeningPrice;

        emit OpeningPriceForIdChanged(id, newOpeningPrice);
    }

    function setAmountOfAirdropParams(IERC20 newAirdropToken, uint256 newValue) external onlyAdmin {
        airdropToken = newAirdropToken;
        amountOfAirdropTokenToOpenner = newValue;

        emit ChangeAirdropParams(address(newAirdropToken), newValue);
    }

    function getBnbPriceToCreate() external view returns (uint256) {
        return _getBnbAmountToFront(creatingPrice);
    }

    function getBnbPriceToOpen(uint256 id, uint256 amount) external view returns (uint256) {
        return _getBnbAmountToFront(_getOpeningPrice(id, amount));
    }

    function getBnbPriceToOpenBatchIds(uint256[] memory ids, uint256 amount)
        external
        view
        returns (uint256[] memory result)
    {
        if (ids.length == 0) {
            return result;
        }

        result = new uint256[](ids.length);
        for (uint256 i = 0; i < ids.length; ++i) {
            result[i] = _getBnbAmountToFront(_getOpeningPrice(ids[i], amount));
        }
    }

    function getRestPrizesLength(uint256 id) external view returns (uint256) {
        return _prizes[id].length;
    }

    function getRestPrizesInfo(
        uint256 id,
        uint256 indexFrom,
        uint256 indexTo
    ) external view returns (ExilonNftLootboxLibrary.WinningPlace[] memory result) {
        uint256 fullLength = _prizes[id].length;
        if (indexFrom >= indexTo || indexTo > fullLength) {
            return result;
        }

        result = new ExilonNftLootboxLibrary.WinningPlace[](indexTo - indexFrom);

        address fundsHolder = idsToFundsHolders[id];
        for (uint256 i = 0; i < indexTo - indexFrom; ++i) {
            result[i] = _prizes[id][i + indexFrom];
            for (uint256 j = 0; j < result[i].prizesInfo.length; ++j) {
                if (result[i].prizesInfo[j].tokenType == ExilonNftLootboxLibrary.TokenType.ERC20) {
                    result[i].prizesInfo[j].amount =
                        (IERC20(result[i].prizesInfo[j].tokenAddress).balanceOf(fundsHolder) *
                            result[i].prizesInfo[j].amount) /
                        _totalSharesOfERC20[id][result[i].prizesInfo[j].tokenAddress];
                }
            }
        }
    }

    function creatorToIdsLen(address creator) external view returns (uint256) {
        return _creatorToIds[creator].length();
    }

    function creatorToIds(
        address creator,
        uint256 indexFrom,
        uint256 indexTo
    ) external view returns (uint256[] memory result) {
        uint256 fullLength = _creatorToIds[creator].length();
        if (indexFrom >= indexTo || indexTo > fullLength) {
            return result;
        }

        result = new uint256[](indexTo - indexFrom);
        for (uint256 i = indexFrom; i < indexTo; ++i) {
            result[i - indexFrom] = _creatorToIds[creator].at(i);
        }
    }

    function idsToCreatorBatch(uint256[] memory ids)
        external
        view
        returns (address[] memory result)
    {
        if (ids.length == 0) {
            return result;
        }

        result = new address[](ids.length);
        for (uint256 i = 0; i < ids.length; ++i) {
            result[i] = idsToCreator[ids[i]];
        }
    }

    struct _withdrawPrizeStack {
        ExilonNftLootboxLibrary.WinningPlace[] prizes;
        uint256 restLootboxes;
        address fundsHolder;
        uint256 nonce;
        uint256 lastIndexWithdrawTokens;
        uint256 lastIndexCreators;
        ExilonNftLootboxLibrary.LootBoxType boxType;
        uint256 minRandomPercentage;
        uint256 maxRandomPercentage;
        uint256 powParameter;
        uint256 usdReceive;
        address creator;
    }

    function _withdrawPrize(
        address redeemer,
        uint256 id,
        uint256 amount
    ) private {
        require(amount > 0, "ExilonNftLootboxMaster: Low amount");
        require(exilonNftLootboxMain.isMerging(id) == false, "ExilonNftLootboxMaster: Merging");

        exilonNftLootboxMain.burn(redeemer, id, amount);

        _withdrawPrizeStack memory stack;
        stack.boxType = exilonNftLootboxMain.lootboxType(id);

        stack.creator = idsToCreator[id];
        if (msg.sender != stack.creator) {
            uint256 usdPrice = _getOpeningPrice(id, amount);

            if (stack.boxType != ExilonNftLootboxLibrary.LootBoxType.DEFAULT) {
                _lastPurchase[id].price = usdPrice;
                _lastPurchase[id].timestamp = block.timestamp;
            }

            uint256 bnbAmount = _checkFees(usdPrice);
            _processFeeTransferOpening(id, bnbAmount);
        } else {
            require(msg.value == 0, "ExilonNftLootboxMaster: For creator open is free");
        }

        _airdropToOpenner();

        stack.prizes = _prizes[id];
        stack.restLootboxes = lootxesAmount[id];
        stack.fundsHolder = idsToFundsHolders[id];
        stack.nonce = _nonce;

        ExilonNftLootboxLibrary.TokenInfo[]
            memory successWithdrawTokens = new ExilonNftLootboxLibrary.TokenInfo[](
                ExilonNftLootboxLibrary.MAX_TOKENS_IN_LOOTBOX
            );

        address[] memory creators;
        if (stack.boxType != ExilonNftLootboxLibrary.LootBoxType.DEFAULT) {
            creators = new address[](amount);
        } else {
            creators = new address[](1);
            creators[0] = idsToCreator[id];
        }

        stack.minRandomPercentage = minRandomPercentage;
        stack.maxRandomPercentage = maxRandomPercentage;
        stack.powParameter = powParameter;

        for (uint256 i = 0; i < amount; ++i) {
            uint256 winningIndex = ExilonNftLootboxLibrary.getWinningIndex(
                stack.prizes,
                ExilonNftLootboxLibrary.getRandomNumber(++stack.nonce, stack.restLootboxes)
            );
            --stack.restLootboxes;

            (
                stack.prizes[winningIndex].prizesInfo,
                successWithdrawTokens,
                stack.lastIndexWithdrawTokens,
                stack.nonce,
                stack.usdReceive
            ) = _withdrawWinningPlace(
                _withdrawWinningPlaceInputStruct({
                    prizeInfo: stack.prizes[winningIndex].prizesInfo,
                    fundsHolder: stack.fundsHolder,
                    winningPlaceAmounts: stack.prizes[winningIndex].placeAmounts,
                    id: id,
                    lastIndex: stack.lastIndexWithdrawTokens,
                    nonce: stack.nonce,
                    minRandomPercentage: stack.minRandomPercentage,
                    maxRandomPercentage: stack.maxRandomPercentage,
                    powParameter: stack.powParameter,
                    successWithdrawTokens: successWithdrawTokens,
                    boxType: stack.boxType
                })
            );

            address creator;
            if (stack.boxType != ExilonNftLootboxLibrary.LootBoxType.DEFAULT) {
                creator = _winningPlaceCreator[id][winningIndex];
                numberOfCreatorsOpenedLootboxes[creator][id] += 1;
                creators[stack.lastIndexCreators] = creator;
                ++stack.lastIndexCreators;
            } else {
                creator = stack.creator;
            }

            stack.prizes = ExilonNftLootboxLibrary.removeWinningPlace(
                stack.prizes,
                winningIndex,
                _prizes[id],
                stack.boxType != ExilonNftLootboxLibrary.LootBoxType.DEFAULT,
                _winningPlaceCreator[id]
            );

            if (stack.boxType == ExilonNftLootboxLibrary.LootBoxType.MEGA_LOOTBOX_RESERVE) {
                exilonNftLootboxMain.refundToUser(
                    msg.sender,
                    creator,
                    stack.usdReceive,
                    defaultOpeningPrice[id]
                );
            }
        }

        {
            uint256 numberToDecrease = ExilonNftLootboxLibrary.MAX_TOKENS_IN_LOOTBOX -
                stack.lastIndexWithdrawTokens;

            assembly {
                mstore(successWithdrawTokens, sub(mload(successWithdrawTokens), numberToDecrease))
            }
        }

        if (stack.boxType != ExilonNftLootboxLibrary.LootBoxType.DEFAULT) {
            uint256 numberToDecrease = amount - stack.lastIndexCreators;
            assembly {
                mstore(creators, sub(mload(creators), numberToDecrease))
            }
        }

        lootxesAmount[id] = stack.restLootboxes;
        _nonce = stack.nonce;

        emit WithdrawLootbox(msg.sender, id, amount);
        emit SuccessfullyWithdrawnTokens(msg.sender, successWithdrawTokens, creators);

        if (stack.restLootboxes == 0) {
            _deleteId(id, stack.fundsHolder);
        }
    }

    function _deleteId(uint256 id, address fundsHolder) private {
        IFundsHolder(fundsHolder).selfDestruct();
        delete idsToFundsHolders[id];
        delete idsToCreator[id];
        delete _prizes[id];
        delete lootxesAmount[id];
        delete defaultOpeningPrice[id];

        emit IdDeleted(id, fundsHolder);
    }

    function _processFeeTransferOpening(uint256 id, uint256 bnbAmount) private {
        if (exilonNftLootboxMain.lootboxType(id) == ExilonNftLootboxLibrary.LootBoxType.DEFAULT) {
            uint256 amountToCreator = (bnbAmount * creatorPercentage) / 10_000;

            // creator is not a contract and shouldn't fail
            address creator = idsToCreator[id];
            (bool success, ) = creator.call{value: amountToCreator}("");
            require(success, "ExilonNftLootboxMaster: Transfer to creator");

            emit TransferFeeToCreator(creator, amountToCreator);

            _processFeeTransferOnFeeReceiver();
        } else {
            _processFeeTransferOnFeeReceiver();
        }
    }

    function _getOpeningPrice(uint256 id, uint256 amount) private view returns (uint256) {
        uint256 minPrice = defaultOpeningPrice[id] * amount;
        if (exilonNftLootboxMain.lootboxType(id) != ExilonNftLootboxLibrary.LootBoxType.DEFAULT) {
            LootboxPurchaseInfo memory lastPurchase = _lastPurchase[id];

            if (
                lastPurchase.timestamp == 0 ||
                lastPurchase.price == 0 ||
                lastPurchase.timestamp + priceTimeDelta < block.timestamp
            ) {
                return minPrice;
            } else {
                uint256 maxPrice = (minPrice * maxOpeningPricePercentage) / 10_000;
                uint256 priceNow = lastPurchase.price +
                    (minPrice * priceDeltaPercentage * (amount - 1)) /
                    10_000;
                if (priceNow > maxPrice) {
                    priceNow = maxPrice;
                }
                return priceNow;
            }
        } else {
            return minPrice;
        }
    }

    function _airdropToOpenner() private {
        (bool success, uint256 amount) = ExilonNftLootboxLibrary.sendTokenCarefully(
            airdropToken,
            amountOfAirdropTokenToOpenner,
            false
        );

        if (!success) {
            emit BadAirdropTransfer(msg.sender, amount);
        }
    }

    struct _withdrawWinningPlaceInputStruct {
        ExilonNftLootboxLibrary.TokenInfo[] prizeInfo;
        address fundsHolder;
        uint256 winningPlaceAmounts;
        uint256 id;
        uint256 lastIndex;
        uint256 nonce;
        uint256 minRandomPercentage;
        uint256 maxRandomPercentage;
        uint256 powParameter;
        ExilonNftLootboxLibrary.TokenInfo[] successWithdrawTokens;
        ExilonNftLootboxLibrary.LootBoxType boxType;
    }

    function _withdrawWinningPlace(_withdrawWinningPlaceInputStruct memory input)
        private
        returns (
            ExilonNftLootboxLibrary.TokenInfo[] memory,
            ExilonNftLootboxLibrary.TokenInfo[] memory,
            uint256,
            uint256,
            uint256 usdReceive
        )
    {
        for (uint256 i = 0; i < input.prizeInfo.length; ++i) {
            uint256 balanceBefore;
            uint256 newPrizeInfoAmount;
            if (input.prizeInfo[i].tokenType == ExilonNftLootboxLibrary.TokenType.ERC20) {
                uint256 totalShares = _totalSharesOfERC20[input.id][
                    input.prizeInfo[i].tokenAddress
                ];

                ++input.nonce;
                ExilonNftLootboxLibrary.getWinningAmountOutputStruct
                    memory getWinningAmountOutput = ExilonNftLootboxLibrary.getWinningAmount(
                        ExilonNftLootboxLibrary.getWinningAmountInputStruct({
                            totalShares: totalShares,
                            prizeInfoAmount: input.prizeInfo[i].amount,
                            tokenAddress: input.prizeInfo[i].tokenAddress,
                            fundsHolder: input.fundsHolder,
                            winningPlaceAmounts: input.winningPlaceAmounts,
                            nonce: input.nonce,
                            minRandomPercentage: input.minRandomPercentage,
                            maxRandomPercentage: input.maxRandomPercentage,
                            powParameter: input.powParameter
                        })
                    );

                input.prizeInfo[i].amount = getWinningAmountOutput.rawAmount;
                newPrizeInfoAmount = getWinningAmountOutput.newPrizeInfoAmount;

                _totalSharesOfERC20[input.id][input.prizeInfo[i].tokenAddress] =
                    totalShares -
                    getWinningAmountOutput.sharesAmount;

                balanceBefore = IERC20(input.prizeInfo[i].tokenAddress).balanceOf(msg.sender);
            } else {
                newPrizeInfoAmount = input.prizeInfo[i].amount;
            }

            if (IFundsHolder(input.fundsHolder).withdrawToken(input.prizeInfo[i], msg.sender)) {
                uint256 receiveAmount;
                (
                    input.successWithdrawTokens,
                    input.lastIndex,
                    receiveAmount
                ) = ExilonNftLootboxLibrary.addTokenInfoToAllTokensArray(
                    ExilonNftLootboxLibrary.addTokenInfoToAllTokensArrayInputStruct({
                        prizeInfo: input.prizeInfo[i],
                        balanceBefore: balanceBefore,
                        lastIndex: input.lastIndex,
                        successWithdrawTokens: input.successWithdrawTokens
                    })
                );

                if (
                    input.boxType == ExilonNftLootboxLibrary.LootBoxType.MEGA_LOOTBOX_RESERVE &&
                    input.prizeInfo[i].tokenType == ExilonNftLootboxLibrary.TokenType.ERC20
                ) {
                    usdReceive += ExilonNftLootboxLibrary.getUsdPriceOfAToken(
                        pancakeRouter,
                        usdToken,
                        _weth,
                        input.prizeInfo[i].tokenAddress,
                        receiveAmount
                    );
                }
            }
            input.prizeInfo[i].amount = newPrizeInfoAmount;
        }

        return (
            input.prizeInfo,
            input.successWithdrawTokens,
            input.lastIndex,
            input.nonce,
            usdReceive
        );
    }
}
