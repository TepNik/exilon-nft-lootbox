// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.11;

import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";

import "./pancake-swap/interfaces/IPancakeRouter02.sol";

import "./ExilonNftLootboxLibrary.sol";
import "./FundsHolder.sol";
import "./FeesCalculator.sol";
import "./interfaces/IExilonNftLootboxMain.sol";

contract ExilonNftLootboxMaster is ERC1155Holder, FeesCalculator {
    using SafeERC20 for IERC20;

    // public

    IExilonNftLootboxMain public immutable exilonNftLootboxMain;

    // mapping that connects ids with the contract that holds the funds of this id
    mapping(uint256 => address) public idsToFundsHolders;
    mapping(uint256 => address) public idsToCreator;

    // info abount prizes
    mapping(uint256 => ExilonNftLootboxLibrary.WinningPlace[]) public prizes;
    mapping(uint256 => uint256) public lootxesAmount;

    // info about prices
    uint256 public creatingPrice;
    uint256 public minimumOpeningPrice;
    mapping(uint256 => uint256) public openingPrice;
    uint256 public creatorPercentage = 5_000; // 50%

    // random parameters
    uint256 minRandomPercentage = 9_000; // 90%
    uint256 maxRandomPercentage = 15_000; // 150%
    uint256 powParameter = 5;

    uint256 public amountOfExilonToOpenner;

    // addresses info
    IERC20 public immutable exilon;
    address public immutable masterContract;

    // private

    mapping(uint256 => mapping(address => uint256)) private _totalSharesOfERC20;

    uint256 private _lastId;
    uint256 private _nonce;

    event LootboxMaded(address indexed maker, uint256 id, uint256 amount);
    event WithdrawLootbox(address indexed maker, uint256 id, uint256 amount);
    event IdDeleted(uint256 id, address indexed fundsHolder);
    event SuccessfullyWithdrawnTokens(
        address indexed user,
        ExilonNftLootboxLibrary.TokenInfo[] tokens
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
        IExilonNftLootboxMain _exilonNftLootboxMain
    ) FeesCalculator(_usdToken, _pancakeRouter, _feeReceiver) {
        exilon = _exilon;
        uint256 oneExilon = 10**IERC20Metadata(address(_exilon)).decimals();
        amountOfExilonToOpenner = oneExilon;

        uint256 oneDollar = 10**IERC20Metadata(_usdToken).decimals();
        minimumOpeningPrice = oneDollar;
        creatingPrice = oneDollar;

        exilonNftLootboxMain = _exilonNftLootboxMain;
        _exilonNftLootboxMain.initMaster();

        FundsHolder _masterContract = new FundsHolder();
        _masterContract.init();
        masterContract = address(_masterContract);

        emit ChangeAmountOfExilonToOpenner(oneExilon);
        emit PriceChanges(oneDollar, oneDollar, creatorPercentage);
        emit RandomParamsChange(minRandomPercentage, maxRandomPercentage, powParameter);
    }

    // max - 200 different tokens for all winning places
    function makeLootBox(
        ExilonNftLootboxLibrary.WinningPlace[] calldata winningPlaces,
        uint256 _openingPrice,
        bool onMarket,
        string memory _uri
    ) external payable nonReentrant onlyEOA {
        require(winningPlaces.length > 0, "ExilonNftLootbox: Must be at least one winning place");

        _checkFees(creatingPrice);
        _processFeeTransferOnFeeReceiver();

        // get total information about tokens in all winningPlaces
        (
            ExilonNftLootboxLibrary.TokenInfo[] memory allTokensInfo,
            uint256 amountOfLootBoxes
        ) = ExilonNftLootboxLibrary.processTokensInfo(winningPlaces);

        uint256 lastId = _lastId;
        _lastId = lastId + 1;
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

        require(_openingPrice >= minimumOpeningPrice, "ExilonNftLootbox: Opening price is too low");
        openingPrice[lastId] = _openingPrice;

        idsToCreator[lastId] = msg.sender;

        FundsHolder fundsHolder = FundsHolder(Clones.clone(masterContract));
        fundsHolder.init();
        idsToFundsHolders[lastId] = address(fundsHolder);

        ExilonNftLootboxLibrary.transferFundsToFundsHolder(
            allTokensInfo,
            address(fundsHolder),
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
            "ExilonNftLootbox: Not enough ids on market"
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
        require(_creatorPercentage <= 10_000, "ExilonNftLootbox: Too big percentage");

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
            "ExilonNftLootbox: Wrong percentage"
        ); // 50% min and 1000% max
        require(_powParameter >= 1 && _powParameter <= 8, "ExilonNftLootbox: Wrong pow parameter");

        minRandomPercentage = _minRandomPercentage;
        maxRandomPercentage = _maxRandomPercentage;
        powParameter = _powParameter;

        emit RandomParamsChange(_minRandomPercentage, _maxRandomPercentage, _powParameter);
    }

    function setOpeningPriceForId(uint256 id, uint256 newOpeningPrice)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(lootxesAmount[id] > 0, "ExilonNftLootbox: No such id");

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

    function getRestPrizesInfo(uint256 id)
        external
        view
        returns (ExilonNftLootboxLibrary.WinningPlace[] memory result)
    {
        result = prizes[id];
        address _fundsHolder = idsToFundsHolders[id];
        for (uint256 i = 0; i < result.length; ++i) {
            for (uint256 j = 0; j < result[i].prizesInfo.length; ++j) {
                if (result[i].prizesInfo[j].tokenType == ExilonNftLootboxLibrary.TokenType.ERC20) {
                    result[i].prizesInfo[j].amount =
                        (IERC20(result[i].prizesInfo[j].tokenAddress).balanceOf(_fundsHolder) *
                            result[i].prizesInfo[j].amount) /
                        _totalSharesOfERC20[id][result[i].prizesInfo[j].tokenAddress];
                }
            }
        }
    }

    function _withdrawPrize(address redeemer, uint256[2] memory idAndAmount) private {
        require(idAndAmount[1] > 0, "ExilonNftLootbox: Low amount");

        exilonNftLootboxMain.burn(redeemer, idAndAmount[0], idAndAmount[1]);

        if (msg.sender != idsToCreator[idAndAmount[0]]) {
            uint256 bnbAmount = _checkFees(openingPrice[idAndAmount[0]] * idAndAmount[1]);
            _processFeeTransferOpening(idAndAmount[0], bnbAmount);
        } else {
            require(msg.value == 0, "ExilonNftLootbox: For creator open free");
        }

        _sendExilonToOpenner();

        ExilonNftLootboxLibrary.WinningPlace[] memory _prizes = prizes[idAndAmount[0]];
        uint256 restLootboxes = lootxesAmount[idAndAmount[0]];
        address _fundsHolder = idsToFundsHolders[idAndAmount[0]];
        uint256 nonce = _nonce;

        ExilonNftLootboxLibrary.TokenInfo[]
            memory successWithdrawTokens = new ExilonNftLootboxLibrary.TokenInfo[](
                ExilonNftLootboxLibrary.MAX_TOKENS_IN_LOOTBOX
            );
        uint256 lastIndex = 0;

        uint256[3] memory randomParameters = [
            minRandomPercentage,
            maxRandomPercentage,
            powParameter
        ];

        for (uint256 i = 0; i < idAndAmount[1]; ++i) {
            uint256 randomNumber = ExilonNftLootboxLibrary.getRandomNumber(++nonce, restLootboxes);
            restLootboxes -= 1;

            uint256 winningIndex = ExilonNftLootboxLibrary.getWinningIndex(_prizes, randomNumber);

            (
                _prizes[winningIndex].prizesInfo,
                successWithdrawTokens,
                lastIndex,
                nonce
            ) = _withdrawWinningPlace(
                _prizes[winningIndex].prizesInfo,
                _fundsHolder,
                [
                    _prizes[winningIndex].placeAmounts,
                    idAndAmount[0],
                    lastIndex,
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

        uint256 numberToDecrease = ExilonNftLootboxLibrary.MAX_TOKENS_IN_LOOTBOX - lastIndex;
        assembly {
            mstore(successWithdrawTokens, sub(mload(successWithdrawTokens), numberToDecrease))
        }

        lootxesAmount[idAndAmount[0]] = restLootboxes;
        _nonce = nonce;

        if (restLootboxes == 0) {
            _deleteId(idAndAmount[0], _fundsHolder);
        }

        emit WithdrawLootbox(msg.sender, idAndAmount[0], idAndAmount[1]);
        emit SuccessfullyWithdrawnTokens(msg.sender, successWithdrawTokens);
    }

    function _deleteId(uint256 id, address fundsHolder) private {
        FundsHolder(fundsHolder).selfDestruct();
        delete idsToFundsHolders[id];
        delete idsToCreator[id];
        delete prizes[id];
        delete lootxesAmount[id];
        delete openingPrice[id];

        emit IdDeleted(id, fundsHolder);
    }

    function _processFeeTransferOpening(uint256 id, uint256 bnbAmount) private {
        uint256 amountToCreator = (bnbAmount * creatorPercentage) / 10_000;

        // creator is not a contract and shouldn't fail
        address creator = idsToCreator[id];
        (bool success, ) = creator.call{value: amountToCreator}("");
        require(success, "ExilonNftLootbox: Transfer to creator");

        emit TransferFeeToCreator(creator, amountToCreator);

        _processFeeTransferOnFeeReceiver();
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

            if (FundsHolder(fundsHolder).withdrawToken(prizeInfo[i], msg.sender)) {
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
