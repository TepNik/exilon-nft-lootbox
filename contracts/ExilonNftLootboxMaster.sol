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
import "./FeeSender.sol";
import "./FeeCalculator.sol";
import "./interfaces/IExilonNftLootboxMain.sol";
import "./interfaces/IFundsHolderFactory.sol";
import "./interfaces/IFundsHolder.sol";
import "./interfaces/IExilonNftLootboxMaster.sol";
import "./interfaces/IPriceHolder.sol";

contract ExilonNftLootboxMaster is
    ERC1155Holder,
    FeeCalculator,
    FeeSender,
    IExilonNftLootboxMaster
{
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.UintSet;

    // Contract ERC1155 for creating lootboxes
    IExilonNftLootboxMain public immutable exilonNftLootboxMain;
    // Contract for creating funds holder contracts
    IFundsHolderFactory public immutable fundsHolderFactory;
    // Contract to get price information
    IPriceHolder public immutable priceHolder;

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

    // Parameters for random
    uint256 public minRandomPercentage = 9_000; // 90%
    uint256 public maxRandomPercentage = 15_000; // 150%
    uint256 public powParameter = 5;
    uint256 private _nonce;

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
    event CreatorWithdraw(
        address indexed creator,
        address indexed user,
        uint256 id,
        uint256 amountOfLootboxes
    );
    event IdDeleted(uint256 id, address indexed fundsHolder);
    event SuccessfullyWithdrawnTokens(
        address indexed user,
        ExilonNftLootboxLibrary.TokenInfo[] tokens,
        address[] creators,
        uint256[] creatorsAmounts
    );
    event TransferFeeToCreator(address indexed creator, uint256 bnbAmount);
    event MergeMaded(uint256 idFrom, uint256 idTo);

    event RandomParamsChange(
        uint256 newMinRandomPercentage,
        uint256 newMaxRandomPercentage,
        uint256 newPowParameter
    );

    event ChangeAirdropParams(address airdropToken, uint256 airdropAmount);

    event GoodAirdropTransfer(address indexed token, address indexed to, uint256 amount);
    event BadAirdropTransfer(
        address indexed token,
        address indexed to,
        uint256 amount,
        string transferError
    );

    constructor(
        IERC20 _exilon,
        IERC20 _airdropToken,
        address _usdToken,
        IPancakeRouter02 _pancakeRouter,
        address _feeReceiver,
        IAccess _accessControl,
        IExilonNftLootboxMain _exilonNftLootboxMain,
        IFundsHolderFactory _fundsHolderFactory,
        IPriceHolder _priceHolder
    )
        FeeCalculator(_usdToken, _pancakeRouter)
        FeeSender(_feeReceiver)
        AccessConnector(_accessControl)
    {
        exilon = _exilon;

        uint256 oneAirdropToken = 10**IERC20Metadata(address(_airdropToken)).decimals();
        amountOfAirdropTokenToOpenner = oneAirdropToken;
        airdropToken = _airdropToken;

        exilonNftLootboxMain = _exilonNftLootboxMain;
        _exilonNftLootboxMain.init(address(_priceHolder));

        fundsHolderFactory = _fundsHolderFactory;
        _fundsHolderFactory.init();

        priceHolder = _priceHolder;
        _priceHolder.init();

        emit ChangeAirdropParams(address(_airdropToken), oneAirdropToken);
        emit RandomParamsChange(minRandomPercentage, maxRandomPercentage, powParameter);
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

        _checkFees(priceHolder.creatingPrice());
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

        priceHolder.setDefaultOpeningPrice(lastId, _openingPrice);

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
        require(
            exilonNftLootboxMain.balanceOf(msg.sender, id) >= amount,
            "ExilonNftLootboxMaster: Not enough ids"
        );
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

    function processMerge(uint256 idFrom, uint256 idTo) external onlyLootboxMain {
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
                stack.allTokensInfoFrom[i].amount = IERC20(stack.allTokensInfoFrom[i].tokenAddress)
                    .balanceOf(stack.fundsHolderFrom);
            }

            require(
                IFundsHolder(stack.fundsHolderFrom).withdrawToken(
                    stack.allTokensInfoFrom[i],
                    stack.fundsHolderTo
                ),
                "ExilonNftLootboxMaster: Merge transfer failed"
            );

            if (stack.allTokensInfoFrom[i].tokenType == ExilonNftLootboxLibrary.TokenType.ERC20) {
                ExilonNftLootboxLibrary.processMergeInfo(
                    ExilonNftLootboxLibrary.processMergeInfoInputStruct({
                        idFrom: idFrom,
                        idTo: idTo,
                        tokenAddress: stack.allTokensInfoFrom[i].tokenAddress,
                        balanceBefore: balanceBefore,
                        fundsHolderTo: stack.fundsHolderTo,
                        winningPlacesFrom: stack.winningPlacesFrom
                    }),
                    _totalSharesOfERC20,
                    _prizes
                );
            }
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
        exilonNftLootboxMain.mint(address(this), idTo, stack.totalLootboxes, "");

        emit MergeMaded(idFrom, idTo);
    }

    function removeWinningPlace(
        uint256 id,
        uint256 index,
        address owner
    ) external onlyManagerOrAdmin {
        // TODO
    }

    function deleteId(uint256 id) external onlyLootboxMain {
        address fundsHolder = idsToFundsHolders[id];
        IFundsHolder(fundsHolder).selfDestruct();
        delete idsToFundsHolders[id];
        delete idsToCreator[id];
        delete _prizes[id];

        emit IdDeleted(id, fundsHolder);
    }

    function setWinningPlacesToTheCreator(uint256 id) external override onlyLootboxMain {
        uint256 length = _prizes[id].length;
        address creator = idsToCreator[id];
        for (uint256 i = 0; i < length; ++i) {
            _winningPlaceCreator[id][i] = creator;
        }
    }

    function withdrawToken(IERC20 token, uint256 amount) external onlyAdmin nonReentrant {
        ExilonNftLootboxLibrary.sendTokenCarefully(token, amount, true);
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

    function setAmountOfAirdropParams(IERC20 newAirdropToken, uint256 newValue) external onlyAdmin {
        airdropToken = newAirdropToken;
        amountOfAirdropTokenToOpenner = newValue;

        emit ChangeAirdropParams(address(newAirdropToken), newValue);
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
        address[] creators;
        uint256[] creatorsAmounts;
    }

    function _withdrawPrize(
        address redeemer,
        uint256 id,
        uint256 amount
    ) private {
        require(amount > 0, "ExilonNftLootboxMaster: Low amount");
        require(exilonNftLootboxMain.isMerging(id) == false, "ExilonNftLootboxMaster: Merging");

        _withdrawPrizeStack memory stack;
        stack.restLootboxes = exilonNftLootboxMain.totalSupply(id);
        stack.boxType = exilonNftLootboxMain.lootboxType(id);

        stack.creator = idsToCreator[id];
        {
            uint256 usdPrice = priceHolder.makePurchase(
                msg.sender,
                id,
                stack.boxType,
                stack.creator,
                amount
            );
            uint256 bnbAmount = _checkFees(usdPrice);
            _processFeeTransferOpening(id, bnbAmount);
        }

        _airdropToOpenner();

        stack.prizes = _prizes[id];
        stack.fundsHolder = idsToFundsHolders[id];
        stack.nonce = _nonce;

        ExilonNftLootboxLibrary.TokenInfo[]
            memory successWithdrawTokens = new ExilonNftLootboxLibrary.TokenInfo[](
                ExilonNftLootboxLibrary.MAX_TOKENS_IN_LOOTBOX
            );

        if (stack.boxType != ExilonNftLootboxLibrary.LootBoxType.DEFAULT) {
            stack.creators = new address[](amount);
            stack.creatorsAmounts = new uint256[](amount);
        } else {
            stack.creators = new address[](1);
            stack.creatorsAmounts = new uint256[](1);
            stack.creators[0] = idsToCreator[id];
            stack.creatorsAmounts[0] = amount;
        }

        // TODO: Withdraw all tokens if amount==totalSupply

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

                for (uint256 j = 0; j < stack.lastIndexCreators; ++j) {
                    if (stack.creators[j] == creator) {
                        ++stack.creatorsAmounts[j];
                    } else if (j == stack.lastIndexCreators - 1) {
                        stack.creators[stack.lastIndexCreators] = creator;
                        stack.creatorsAmounts[stack.lastIndexCreators] = 1;
                        ++stack.lastIndexCreators;
                    }
                }
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
                    priceHolder.defaultOpeningPrice(id)
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
            {
                address[] memory temp = stack.creators;
                assembly {
                    mstore(temp, sub(mload(temp), numberToDecrease))
                }
                stack.creators = temp;
            }
            {
                uint256[] memory temp = stack.creatorsAmounts;
                assembly {
                    mstore(temp, sub(mload(temp), numberToDecrease))
                }
                stack.creatorsAmounts = temp;
            }
        }

        for (uint256 i = 0; i < stack.creators.length; ++i) {
            numberOfCreatorsOpenedLootboxes[stack.creators[i]][id] += stack.creatorsAmounts[i];

            emit CreatorWithdraw(stack.creators[i], msg.sender, id, stack.creatorsAmounts[i]);
        }

        exilonNftLootboxMain.burn(redeemer, id, amount);

        _nonce = stack.nonce;

        emit WithdrawLootbox(msg.sender, id, amount);
        emit SuccessfullyWithdrawnTokens(
            msg.sender,
            successWithdrawTokens,
            stack.creators,
            stack.creatorsAmounts
        );
    }

    function _processFeeTransferOpening(uint256 id, uint256 bnbAmount) private {
        if (exilonNftLootboxMain.lootboxType(id) == ExilonNftLootboxLibrary.LootBoxType.DEFAULT) {
            uint256 amountToCreator = (bnbAmount * priceHolder.creatorPercentage()) / 10_000;

            // creator is not a contract and shouldn't fail
            address creator = idsToCreator[id];
            (bool success, ) = creator.call{value: amountToCreator}("");
            require(success, "ExilonNftLootboxMaster: Transfer to creator");

            emit TransferFeeToCreator(creator, amountToCreator);
        }
        _processFeeTransferOnFeeReceiver();
    }

    function _airdropToOpenner() private {
        IERC20 _airdropToken = airdropToken;
        (bool success, uint256 amount, string memory transferError) = ExilonNftLootboxLibrary
            .sendTokenCarefully(_airdropToken, amountOfAirdropTokenToOpenner, false);

        if (!success) {
            emit BadAirdropTransfer(address(_airdropToken), msg.sender, amount, transferError);
        } else {
            emit GoodAirdropTransfer(address(_airdropToken), msg.sender, amount);
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
