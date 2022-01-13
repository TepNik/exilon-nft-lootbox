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

contract ExilonNftLootboxMaster is ERC1155Holder, FeesCalculator {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.UintSet;

    // Contract ERC1155 for creating lootboxes
    IExilonNftLootboxMain public immutable exilonNftLootboxMain;
    // Contract for creating funds holder contracts
    IFundsHolderFactory public immutable fundsHolderFactory;

    // Connects ids with the contract that holds the funds of this id
    mapping(uint256 => address) public idsToFundsHolders;
    // Connects ids with the creator address
    mapping(uint256 => address) public idsToCreator;
    // Connects creator address with the ids, that he maded
    mapping(address => EnumerableSet.UintSet) private _creatorToIds;
    // Last id
    uint256 private _lastId;

    // Info abount prizes
    mapping(uint256 => ExilonNftLootboxLibrary.WinningPlace[]) private prizes;
    // Connects id with the amount of an unpacked lootboxes
    mapping(uint256 => uint256) public lootxesAmount;

    // Amount in USD for creating lootbox
    uint256 public creatingPrice;
    // Minimal amount in USD for openning price
    uint256 public minimumOpeningPrice;
    // Connects id with it's openning price
    mapping(uint256 => uint256) public openingPrice;
    // Percentage from openning price that the creators will get (100% - 10_000)
    uint256 public creatorPercentage = 5_000; // 50%

    // Parameters for random
    uint256 public minRandomPercentage = 9_000; // 90%
    uint256 public maxRandomPercentage = 15_000; // 150%
    uint256 public powParameter = 5;
    uint256 private _nonce;

    // Amount of exilon tokens that the openers of lootboxes will get
    uint256 public amountOfExilonToOpenner;

    // Addresses info
    IERC20 public immutable exilon;

    // Connects an id and token address with the available amount of this token for this id
    mapping(uint256 => mapping(address => uint256)) private _totalSharesOfERC20;

    event LootboxMaded(address indexed maker, uint256 id, uint256 amount);
    event WithdrawLootbox(address indexed maker, uint256 id, uint256 amount);
    event IdDeleted(uint256 id, address indexed fundsHolder);
    event SuccessfullyWithdrawnTokens(
        address indexed user,
        ExilonNftLootboxLibrary.TokenInfo[] tokens,
        address[] creators
    );
    event TransferFeeToCreator(address indexed creator, uint256 bnbAmount);

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
    event OpeningPriceForIdChanged(uint256 id, uint256 newOpeningPrice);
    event ChangeAmountOfExilonToOpenner(uint256 newValue);

    event BadExilonTransfer(address indexed to, uint256 amount);

    constructor(
        IERC20 _exilon,
        address _usdToken,
        IPancakeRouter02 _pancakeRouter,
        address _feeReceiver,
        IExilonNftLootboxMain _exilonNftLootboxMain,
        IFundsHolderFactory _fundsHolderFactory
    ) FeesCalculator(_usdToken, _pancakeRouter, _feeReceiver) {
        exilon = _exilon;
        uint256 oneExilon = 10**IERC20Metadata(address(_exilon)).decimals();
        amountOfExilonToOpenner = oneExilon;

        minimumOpeningPrice = _oneUsd;
        creatingPrice = _oneUsd;

        exilonNftLootboxMain = _exilonNftLootboxMain;
        _exilonNftLootboxMain.init();

        fundsHolderFactory = _fundsHolderFactory;
        _fundsHolderFactory.init();

        emit ChangeAmountOfExilonToOpenner(oneExilon);
        emit PriceChanges(_oneUsd, _oneUsd, creatorPercentage);
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
        openingPrice[lastId] = _openingPrice;

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
            prizes[lastId].push(winningPlaces[i]);
        }

        emit LootboxMaded(msg.sender, lastId, amountOfLootBoxes);
    }

    function withdrawPrize(uint256 id, uint256 amount) external payable nonReentrant onlyEOA {
        _withdrawPrize(msg.sender, [id, amount]);
    }

    function buyId(uint256 id, uint256 amount) external payable nonReentrant onlyEOA {
        require(
            exilonNftLootboxMain.balanceOf(address(this), id) >= amount,
            "ExilonNftLootboxMaster: Not enough ids on market"
        );
        _withdrawPrize(address(this), [id, amount]);
    }

    function withdrawToken(IERC20 token, uint256 amount)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        nonReentrant
    {
        ExilonNftLootboxLibrary.sendTokenCarefully(token, amount, true);
    }

    function setPriceInfo(
        uint256 _creatingPrice,
        uint256 _minimumOpeningPrice,
        uint256 _creatorPercentage
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_creatorPercentage <= 10_000, "ExilonNftLootboxMaster: Too big percentage");

        creatingPrice = _creatingPrice;
        minimumOpeningPrice = _minimumOpeningPrice;
        creatorPercentage = _creatorPercentage;

        emit PriceChanges(_creatingPrice, _minimumOpeningPrice, _creatorPercentage);
    }

    function setRandomParams(
        uint256 _minRandomPercentage,
        uint256 _maxRandomPercentage,
        uint256 _powParameter
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
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

    function setOpeningPriceForId(uint256 id, uint256 newOpeningPrice) external {
        require(
            msg.sender == idsToCreator[id] || hasRole(DEFAULT_ADMIN_ROLE, msg.sender),
            "ExilonNftLootboxMaster: No access"
        );
        require(lootxesAmount[id] > 0, "ExilonNftLootboxMaster: No such id");
        require(
            exilonNftLootboxMain.lootboxType(id) == ExilonNftLootboxLibrary.LootBoxType.DEFAULT,
            "ExilonNftLootboxMaster: Only default"
        );

        openingPrice[id] = newOpeningPrice;

        emit OpeningPriceForIdChanged(id, newOpeningPrice);
    }

    function setAmountOfExilonToOpenner(uint256 newValue) external onlyRole(DEFAULT_ADMIN_ROLE) {
        amountOfExilonToOpenner = newValue;

        emit ChangeAmountOfExilonToOpenner(newValue);
    }

    function getBnbPriceToCreate() external view returns (uint256) {
        return _getBnbAmountToFront(creatingPrice);
    }

    function getBnbPriceToOpen(uint256 id, uint256 amount) external view returns (uint256) {
        return _getBnbAmountToFront(openingPrice[id] * amount);
    }

    function getRestPrizesLength(uint256 id) external view returns (uint256) {
        return prizes[id].length;
    }

    function getRestPrizesInfo(
        uint256 id,
        uint256 indexFrom,
        uint256 indexTo
    ) external view returns (ExilonNftLootboxLibrary.WinningPlace[] memory result) {
        uint256 fullLength = prizes[id].length;
        if (indexFrom > indexTo || indexTo > fullLength || indexTo - indexFrom > fullLength) {
            return result;
        }

        result = new ExilonNftLootboxLibrary.WinningPlace[](indexTo - indexFrom);

        address fundsHolder = idsToFundsHolders[id];
        for (uint256 i = 0; i < indexTo - indexFrom; ++i) {
            result[i] = prizes[id][i + indexFrom];
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

    function creatorToIdsIndex(address creator, uint256 index) external view returns (uint256) {
        return _creatorToIds[creator].at(index);
    }

    function _withdrawPrize(address redeemer, uint256[2] memory idAndAmount) private {
        require(idAndAmount[1] > 0, "ExilonNftLootboxMaster: Low amount");

        exilonNftLootboxMain.burn(redeemer, idAndAmount[0], idAndAmount[1]);

        if (msg.sender != idsToCreator[idAndAmount[0]]) {
            uint256 bnbAmount = _checkFees(openingPrice[idAndAmount[0]] * idAndAmount[1]);
            _processFeeTransferOpening(idAndAmount[0], bnbAmount);
        } else {
            require(msg.value == 0, "ExilonNftLootboxMaster: For creator open free");
        }

        _sendExilonToOpenner();

        ExilonNftLootboxLibrary.WinningPlace[] memory _prizes = prizes[idAndAmount[0]];
        uint256 restLootboxes = lootxesAmount[idAndAmount[0]];
        address fundsHolder = idsToFundsHolders[idAndAmount[0]];
        uint256 nonce = _nonce;

        ExilonNftLootboxLibrary.TokenInfo[]
            memory successWithdrawTokens = new ExilonNftLootboxLibrary.TokenInfo[](
                ExilonNftLootboxLibrary.MAX_TOKENS_IN_LOOTBOX
            );
        uint256 lastIndexWithdrawTokens;

        uint256[3] memory randomParameters = [
            minRandomPercentage,
            maxRandomPercentage,
            powParameter
        ];

        for (uint256 i = 0; i < idAndAmount[1]; ++i) {
            uint256 winningIndex = ExilonNftLootboxLibrary.getWinningIndex(
                _prizes,
                ExilonNftLootboxLibrary.getRandomNumber(++nonce, restLootboxes)
            );
            restLootboxes -= 1;

            (
                _prizes[winningIndex].prizesInfo,
                successWithdrawTokens,
                lastIndexWithdrawTokens,
                nonce
            ) = _withdrawWinningPlace(
                _prizes[winningIndex].prizesInfo,
                fundsHolder,
                [
                    _prizes[winningIndex].placeAmounts,
                    idAndAmount[0],
                    lastIndexWithdrawTokens,
                    nonce,
                    randomParameters[0],
                    randomParameters[1],
                    randomParameters[2]
                ],
                successWithdrawTokens
            );

            _prizes = ExilonNftLootboxLibrary.removeWinningPlace(
                _prizes,
                idAndAmount[0],
                winningIndex,
                prizes
            );
        }

        {
            uint256 numberToDecrease = ExilonNftLootboxLibrary.MAX_TOKENS_IN_LOOTBOX -
                lastIndexWithdrawTokens;
            assembly {
                mstore(successWithdrawTokens, sub(mload(successWithdrawTokens), numberToDecrease))
            }
        }

        lootxesAmount[idAndAmount[0]] = restLootboxes;
        _nonce = nonce;

        emit WithdrawLootbox(msg.sender, idAndAmount[0], idAndAmount[1]);
        // emit SuccessfullyWithdrawnTokens(msg.sender, successWithdrawTokens, idsToCreator[idAndAmount[0]]);
        // TODO

        if (restLootboxes == 0) {
            _deleteId(idAndAmount[0], fundsHolder);
        }
    }

    function _deleteId(uint256 id, address fundsHolder) private {
        IFundsHolder(fundsHolder).selfDestruct();
        delete idsToFundsHolders[id];
        delete idsToCreator[id];
        delete prizes[id];
        delete lootxesAmount[id];
        delete openingPrice[id];

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

    function _sendExilonToOpenner() private {
        (bool success, uint256 amount) = ExilonNftLootboxLibrary.sendTokenCarefully(
            exilon,
            amountOfExilonToOpenner,
            false
        );

        if (!success) {
            emit BadExilonTransfer(msg.sender, amount);
        }
    }

    function _withdrawWinningPlace(
        ExilonNftLootboxLibrary.TokenInfo[] memory prizeInfo,
        // 0 - winningPlaceAmounts, 1 - id, 2 - lastIndex, 3 - nonce, 4 - minRandomPercentage, 5 - maxRandomPercentage, 6 - powParameter
        address fundsHolder,
        uint256[7] memory uint256Parameters,
        ExilonNftLootboxLibrary.TokenInfo[] memory successWithdrawTokens
    )
        private
        returns (
            ExilonNftLootboxLibrary.TokenInfo[] memory,
            ExilonNftLootboxLibrary.TokenInfo[] memory,
            uint256,
            uint256
        )
    {
        for (uint256 i = 0; i < prizeInfo.length; ++i) {
            uint256 balanceBefore;
            uint256 newPrizeInfoAmount;
            if (prizeInfo[i].tokenType == ExilonNftLootboxLibrary.TokenType.ERC20) {
                /* uint256 totalShares = _totalSharesOfERC20[uint256Parameters[1]][
                    prizeInfo[i].tokenAddress
                ]; */

                ++uint256Parameters[3];
                uint256[3] memory winningAmountInfo = ExilonNftLootboxLibrary.getWinningAmount(
                    //totalShares,
                    _totalSharesOfERC20[uint256Parameters[1]][prizeInfo[i].tokenAddress],
                    prizeInfo[i].amount,
                    prizeInfo[i].tokenAddress,
                    fundsHolder,
                    uint256Parameters
                );

                prizeInfo[i].amount = winningAmountInfo[0];
                newPrizeInfoAmount = winningAmountInfo[2];

                /* _totalSharesOfERC20[uint256Parameters[1]][prizeInfo[i].tokenAddress] =
                    totalShares -
                    winningAmountInfo[1]; */
                _totalSharesOfERC20[uint256Parameters[1]][
                    prizeInfo[i].tokenAddress
                ] -= winningAmountInfo[1];

                balanceBefore = IERC20(prizeInfo[i].tokenAddress).balanceOf(msg.sender);
            } else {
                newPrizeInfoAmount = prizeInfo[i].amount;
            }

            if (IFundsHolder(fundsHolder).withdrawToken(prizeInfo[i], msg.sender)) {
                (successWithdrawTokens, uint256Parameters) = ExilonNftLootboxLibrary
                    .addTokenInfoToAllTokensArray(
                        prizeInfo[i],
                        balanceBefore,
                        uint256Parameters,
                        successWithdrawTokens
                    );
            }
            prizeInfo[i].amount = newPrizeInfoAmount;
        }

        return (prizeInfo, successWithdrawTokens, uint256Parameters[2], uint256Parameters[3]);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(AccessControl, ERC1155Receiver)
        returns (bool)
    {
        return
            AccessControl.supportsInterface(interfaceId) ||
            ERC1155Receiver.supportsInterface(interfaceId);
    }
}
