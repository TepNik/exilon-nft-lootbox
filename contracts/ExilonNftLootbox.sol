// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.11;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "./pancake-swap/interfaces/IPancakeRouter02.sol";

import "./ExilonNftLootboxLibrary.sol";
import "./FundsHolder.sol";

contract ExilonNftLootbox is AccessControl, ReentrancyGuard, ERC1155, ERC1155Holder {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.UintSet;

    // public

    // mapping that connects ids with the contract that holds the funds of this id
    mapping(uint256 => address) public idsToFundsHolders;
    mapping(uint256 => address) public idsToCreator;

    // info abount prizes
    mapping(uint256 => ExilonNftLootboxLibrary.WinningPlace[]) public prizes;
    mapping(uint256 => mapping(address => uint256)) public totalSharesOfERC20;
    mapping(uint256 => uint256) public lootxesAmount;

    // info about prices
    uint256 public creatingPrice;
    uint256 public minimumOpeningPrice;
    mapping(uint256 => uint256) public openingPrice;
    uint256 public creatorPercentage = 5_000; // 50%
    uint256 public extraPriceForFront = 500; // 5%

    // random parameters
    uint256 minRandomPercentage = 8_000; // 80%
    uint256 maxRandomPercentage = 30_000; // 300%
    uint256 powParameter = 3;

    uint256 public amountOfExilonToOpenner;

    // addresses info
    IERC20 public immutable exilon;
    address public immutable usdToken;
    address public immutable masterContract;
    IPancakeRouter02 public immutable pancakeRouter;

    address public feeReceiver;

    // private

    address private immutable weth;

    uint256 private _lastId;
    mapping(uint256 => string) private _idsToUri;
    uint256 private _nonce;
    mapping(address => EnumerableSet.UintSet) private _idsUsersHold;

    modifier onlyEOA() {
        require(msg.sender == tx.origin, "ExilonNftLootbox: Only EOA");
        _;
    }

    event LootboxMaded(address indexed maker, uint256 id, uint256 amount);
    event WithdrawLootbox(address indexed maker, uint256 id, uint256 amount);
    event IdDeleted(uint256 id, address indexed fundsHolder);
    event FeesCollected(address indexed user, uint256 bnbAmount, uint256 usdAmount);
    event SuccessfullyWithdrawnTokens(ExilonNftLootboxLibrary.TokenInfo[] tokens);

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
    event ExtraPriceForFrontChange(uint256 newValue);
    event FeeReceiverChange(address newValue);
    event OpeningPriceForIdChanged(uint256 id, uint256 newOpeningPrice);
    event ChangeAmountOfExilonToOpenner(uint256 newValue);

    event BadExilonTransfer(address indexed to, uint256 amount);
    event BadCommissionTransfer(address indexed to, uint256 amount);

    constructor(
        IERC20 _exilon,
        address _usdToken,
        IPancakeRouter02 _pancakeRouter,
        address _feeReceiver
    ) ERC1155("") {
        exilon = _exilon;
        uint256 oneExilon = 10**IERC20Metadata(address(_exilon)).decimals();
        amountOfExilonToOpenner = oneExilon;

        usdToken = _usdToken;
        uint256 oneDollar = 10**IERC20Metadata(_usdToken).decimals();
        minimumOpeningPrice = oneDollar;
        creatingPrice = oneDollar;

        FundsHolder _masterContract = new FundsHolder();
        _masterContract.init();
        masterContract = address(_masterContract);

        pancakeRouter = _pancakeRouter;
        weth = _pancakeRouter.WETH();

        feeReceiver = _feeReceiver;

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);

        emit ChangeAmountOfExilonToOpenner(oneExilon);
        emit FeeReceiverChange(_feeReceiver);
        emit ExtraPriceForFrontChange(extraPriceForFront);
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
            _mint(receiver, lastId, amountOfLootBoxes, "");
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
            totalSharesOfERC20
        );

        for (uint256 i = 0; i < winningPlaces.length; ++i) {
            prizes[lastId].push(winningPlaces[i]);
        }

        _idsToUri[lastId] = _uri;
        emit URI(_uri, lastId);

        emit LootboxMaded(msg.sender, lastId, amountOfLootBoxes);
    }

    function withdrawPrize(uint256 id, uint256 amount) external payable nonReentrant onlyEOA {
        _withdrawPrize(msg.sender, [id, amount]);
    }

    function buyId(uint256 id, uint256 amount) external payable nonReentrant onlyEOA {
        require(
            balanceOf(address(this), id) >= amount,
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

    function setFeeReceiver(address newValue) external onlyRole(DEFAULT_ADMIN_ROLE) {
        feeReceiver = newValue;

        emit FeeReceiverChange(newValue);
    }

    function setExtraPriceForFront(uint256 newValue) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newValue <= 5_000, "ExilonNftLootbox: Too big percentage"); // 50%
        extraPriceForFront = newValue;

        emit ExtraPriceForFrontChange(newValue);
    }

    function uri(uint256 id) public view virtual override returns (string memory) {
        return _idsToUri[id];
    }

    function getBnbPriceToCreate() external view returns (uint256) {
        return _getBnbAmount((creatingPrice * (extraPriceForFront + 10_000)) / 10_000);
    }

    function getBnbPriceToOpen(uint256 id, uint256 amount) external view returns (uint256) {
        return _getBnbAmount((openingPrice[id] * amount * (extraPriceForFront + 10_000)) / 10_000);
    }

    function getUsersIdsLength(address user) external view returns (uint256) {
        return _idsUsersHold[user].length();
    }

    function getUsersIds(
        address user,
        uint256 indexFrom,
        uint256 indexTo
    ) external view returns (uint256[] memory result) {
        uint256 len = _idsUsersHold[user].length();

        if (indexFrom >= indexTo || indexFrom > len || indexTo > len) {
            return new uint256[](0);
        }

        result = new uint256[](indexTo - indexFrom);
        for (uint256 i = indexFrom; i < indexTo; ++i) {
            result[i] = _idsUsersHold[user].at(i);
        }
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
                        totalSharesOfERC20[id][result[i].prizesInfo[j].tokenAddress];
                }
            }
        }
    }

    function _withdrawPrize(
        address redeemer,
        uint256[2] memory idAndAmount
    ) private {
        require(idAndAmount[1] > 0, "ExilonNftLootbox: Low amount");

        _burn(redeemer, idAndAmount[0], idAndAmount[1]);

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

            (_prizes[winningIndex].prizesInfo, successWithdrawTokens, lastIndex, nonce) = _withdrawWinningPlace(
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

            _prizes = ExilonNftLootboxLibrary.removeWinningPlace(_prizes, idAndAmount[0], winningIndex, prizes);
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
        emit SuccessfullyWithdrawnTokens(successWithdrawTokens);
    }

    function _deleteId(uint256 id, address fundsHolder) private {
        FundsHolder(fundsHolder).selfDestruct();
        delete idsToFundsHolders[id];
        delete idsToCreator[id];
        delete prizes[id];
        delete lootxesAmount[id];
        delete openingPrice[id];
        delete _idsToUri[id];

        emit URI("", id);

        emit IdDeleted(id, fundsHolder);
    }

    function _checkFees(uint256 amount) private returns (uint256 bnbAmount) {
        bnbAmount = _getBnbAmount(amount);

        require(msg.value >= bnbAmount, "ExilonNftLootbox: Not enough bnb");

        uint256 amountBack = msg.value - bnbAmount;
        if (amountBack > 0) {
            (bool success, ) = msg.sender.call{value: amountBack}("");
            require(success, "ExilonNftLootbox: Failed transfer back");
        }

        emit FeesCollected(msg.sender, bnbAmount, amount);
    }

    function _processFeeTransferOnFeeReceiver() private {
        address _feeReceiver = feeReceiver;
        uint256 amount = address(this).balance;
        (bool success, ) = _feeReceiver.call{value: amount, gas: 2_000_000}("");
        if (!success) {
            emit BadCommissionTransfer(_feeReceiver, amount);
        }
    }

    function _processFeeTransferOpening(uint256 id, uint256 bnbAmount) private {
        uint256 amountToCreator = (bnbAmount * creatorPercentage) / 10_000;

        // creator is not a contract and shouldn't fail
        (bool success, ) = idsToCreator[id].call{value: amountToCreator}("");
        require(success, "ExilonNftLootbox: Transfer to creator");

        _processFeeTransferOnFeeReceiver();
    }

    function _getBnbAmount(uint256 amount) private view returns (uint256) {
        address[] memory path = new address[](2);
        path[0] = weth;
        path[1] = usdToken;
        return (pancakeRouter.getAmountsIn(amount, path))[0];
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
                /* uint256 totalShares = totalSharesOfERC20[uint256Parameters[1]][
                    prizeInfo[i].tokenAddress
                ]; */

                ++uint256Parameters[3];
                uint256[3] memory winningAmountInfo = ExilonNftLootboxLibrary.getWinningAmount(
                    //totalShares,
                    totalSharesOfERC20[uint256Parameters[1]][prizeInfo[i].tokenAddress],
                    prizeInfo[i].amount,
                    prizeInfo[i].tokenAddress,
                    fundsHolder,
                    uint256Parameters
                );

                prizeInfo[i].amount = winningAmountInfo[0];
                newPrizeInfoAmount = winningAmountInfo[2];

                /* totalSharesOfERC20[uint256Parameters[1]][prizeInfo[i].tokenAddress] =
                    totalShares -
                    winningAmountInfo[1]; */
                totalSharesOfERC20[uint256Parameters[1]][prizeInfo[i].tokenAddress] -= winningAmountInfo[1];

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

    function _beforeTokenTransfer(
        address,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory
    ) internal virtual override {
        for (uint256 i = 0; i < ids.length; ++i) {
            if (from != address(0)) {
                uint256 balanceFrom = balanceOf(from, ids[i]);
                if (amounts[i] > 0 && balanceFrom <= amounts[i]) {
                    _idsUsersHold[from].remove(ids[i]);
                }
            }
            if (to != address(0) && amounts[i] > 0) {
                _idsUsersHold[to].add(ids[i]);
            }
        }
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(AccessControl, ERC1155, ERC1155Receiver)
        returns (bool)
    {
        return
            AccessControl.supportsInterface(interfaceId) ||
            ERC1155.supportsInterface(interfaceId) ||
            ERC1155Receiver.supportsInterface(interfaceId);
    }
}
