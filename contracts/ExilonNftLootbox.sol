// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.10;

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
    uint256 public creatorPercentage = 5000; // 50%
    uint256 public extraPriceForFront = 500; // 5%

    uint256 public amountOfExilonToOpenner;

    // addresses info
    IERC20 public immutable exilon;
    address public immutable usdToken;
    address public immutable masterContract;
    IPancakeRouter02 public immutable pancakeRouter;
    address private immutable weth;

    address public feeReceiver;

    // private

    uint256 private _lastId;
    mapping(uint256 => string) private _idsToUri;
    uint256 private _nonce;
    mapping(address => EnumerableSet.UintSet) private _idsUsersHold;

    event LootboxMaded(address indexed maker, uint256 id, uint256 amount, uint256 openingPrice);
    event WithdrawLootbox(address indexed maker, uint256 id, uint256 amount);
    event IdDeleted(uint256 id, address indexed fundsHolder);

    event PriceChanges(
        uint256 newCreatingPrice,
        uint256 newMinimumOpeningPrice,
        uint256 newCreatorPercentage
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
    }

    // max - 200 different tokens for all winning places
    function makeLootBox(
        ExilonNftLootboxLibrary.WinningPlace[] calldata winningPlaces,
        uint256 _openingPrice,
        bool onMarket,
        string memory _uri
    ) external payable nonReentrant {
        require(msg.sender == tx.origin, "ExilonNftLootbox: Contracts not allowed");
        require(winningPlaces.length > 0, "ExilonNftLootbox: Must be at least one winning place");

        _checkAndTransferFees(creatingPrice);

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

        for (uint256 i = 0; i < allTokensInfo.length; ++i) {
            ExilonNftLootboxLibrary.withdrawToken(
                allTokensInfo[i],
                msg.sender,
                address(fundsHolder),
                true
            );

            if (allTokensInfo[i].tokenType == ExilonNftLootboxLibrary.TokenType.ERC20) {
                totalSharesOfERC20[lastId][allTokensInfo[i].tokenAddress] = allTokensInfo[i].amount;
            }
        }

        for (uint256 i = 0; i < winningPlaces.length; ++i) {
            prizes[lastId].push(winningPlaces[i]);
        }

        _idsToUri[lastId] = _uri;
        emit URI(_uri, lastId);

        emit LootboxMaded(msg.sender, lastId, amountOfLootBoxes, _openingPrice);
    }

    function withdrawPrize(uint256 id, uint256 amount) external payable {
        _withdrawPrize(msg.sender, id, amount);
    }

    function buyId(uint256 id, uint256 amount) external payable {
        require(
            balanceOf(address(this), id) >= amount,
            "ExilonNftLootbox: Not enough ids on market"
        );
        _withdrawPrize(address(this), id, amount);
    }

    function withdrawToken(IERC20 token, uint256 amount)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        nonReentrant
    {
        if (address(token) != address(0)) {
            uint256 tokenBalance = token.balanceOf(address(this));
            if (amount == 0 || amount > tokenBalance) {
                amount = tokenBalance;
            }
            if (amount == 0) {
                return;
            }

            token.safeTransfer(msg.sender, amount);
        } else {
            uint256 ethAmount = address(this).balance;
            if (amount == 0 || amount > ethAmount) {
                amount = ethAmount;
            }
            if (amount == 0) {
                return;
            }

            (bool success, ) = msg.sender.call{value: amount}("");
            require(success, "ExilonNftLootbox: Eth transfer failed");
        }
    }

    function setPriceInfo(
        uint256 _creatingPrice,
        uint256 _minimumOpeningPrice,
        uint256 _creatorPercentage
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_creatorPercentage <= 10000, "ExilonNftLootbox: Too big percentage");

        creatingPrice = _creatingPrice;
        minimumOpeningPrice = _minimumOpeningPrice;
        creatorPercentage = _creatorPercentage;

        emit PriceChanges(_creatingPrice, _minimumOpeningPrice, _creatorPercentage);
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
        extraPriceForFront = newValue;

        emit ExtraPriceForFrontChange(newValue);
    }

    function uri(uint256 id) public view virtual override returns (string memory) {
        return _idsToUri[id];
    }

    function getBnbPriceToCreate() external view returns(uint256) {
        return _getBnbAmount(creatingPrice * (extraPriceForFront + 10000) / 10000);
    }

    function getBnbPriceToOpen(uint256 id, uint256 amount) external view returns(uint256) {
        return _getBnbAmount(openingPrice[id] * amount * (extraPriceForFront + 10000) / 10000);
    }

    function getUsersIds(address user) external view returns (uint256[] memory result) {
        uint256 len = _idsUsersHold[user].length();
        result = new uint256[](len);
        for (uint256 i = 0; i < len; ++i) {
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
        uint256 id,
        uint256 amount
    ) private {
        require(amount > 0, "ExilonNftLootbox: Low amount");

        _burn(redeemer, id, amount);

        if (msg.sender != idsToCreator[id]) {
            _checkAndTransferFees(openingPrice[id] * amount);
        }

        _sendExilonToOpenner();

        uint256 nonce = _nonce;
        ExilonNftLootboxLibrary.WinningPlace[] memory _prizes = prizes[id];
        uint256 restLootboxes = lootxesAmount[id];
        address _fundsHolder = idsToFundsHolders[id];
        for (uint256 i = 0; i < amount; ++i) {
            uint256 randomNumber = uint256(
                keccak256(
                    abi.encodePacked(
                        block.timestamp,
                        block.number,
                        msg.sender,
                        ++nonce,
                        blockhash(block.number - 1),
                        blockhash(block.number - 2),
                        block.coinbase,
                        block.difficulty
                    )
                )
            ) % restLootboxes;
            restLootboxes -= 1;

            uint256 winningIndex = ExilonNftLootboxLibrary.getWinningIndex(_prizes, randomNumber);

            _withdrawWinningPlace(_prizes[winningIndex].prizesInfo, id, _fundsHolder);

            _prizes = ExilonNftLootboxLibrary.removeWinningPlace(_prizes, id, winningIndex, prizes);
        }
        lootxesAmount[id] = restLootboxes;
        _nonce = nonce;

        if (restLootboxes == 0) {
            _deleteId(id, _fundsHolder);
        }

        emit WithdrawLootbox(msg.sender, id, amount);
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

    function _checkAndTransferFees(uint256 amount) private {
        uint256 bnbAmount = _getBnbAmount(amount);

        require(msg.value >= bnbAmount, "ExilonNftLootbox: Not enough bnb");

        uint256 amountBack = msg.value - bnbAmount;
        bool success;
        if (amountBack > 0) {
            (success, ) = msg.sender.call{value: amountBack}("");
            require(success, "ExilonNftLootbox: Failed transfer back");
        }

        address _feeReceiver = feeReceiver;
        (success, ) = _feeReceiver.call{value: bnbAmount, gas: 1_000_000}("");
        if (!success) {
            emit BadCommissionTransfer(_feeReceiver, bnbAmount);
        }
    }

    function _getBnbAmount(uint256 amount) private view returns (uint256) {
        address[] memory path = new address[](2);
        path[0] = weth;
        path[1] = usdToken;
        return (pancakeRouter.getAmountsIn(amount, path))[0];
    }

    function _sendExilonToOpenner() private {
        uint256 _amountOfExilonToOpenner = amountOfExilonToOpenner;
        uint256 balance = exilon.balanceOf(address(this));

        if (_amountOfExilonToOpenner > balance) {
            _amountOfExilonToOpenner = balance;
        }

        if (_amountOfExilonToOpenner > 0) {
            (bool success, ) = address(exilon).call{gas: 1_000_000}(
                abi.encodeWithSelector(
                    IERC20.transfer.selector,
                    msg.sender,
                    _amountOfExilonToOpenner
                )
            );
            if (!success) {
                emit BadExilonTransfer(msg.sender, _amountOfExilonToOpenner);
            }
        }
    }

    function _withdrawWinningPlace(
        ExilonNftLootboxLibrary.TokenInfo[] memory prizeInfo,
        uint256 id,
        address fundsHolder
    ) private {
        for (uint256 j = 0; j < prizeInfo.length; ++j) {
            if (prizeInfo[j].tokenType == ExilonNftLootboxLibrary.TokenType.ERC20) {
                uint256 _totalShares = totalSharesOfERC20[id][prizeInfo[j].tokenAddress];
                uint256 oldAmount = prizeInfo[j].amount;

                prizeInfo[j].amount =
                    (IERC20(prizeInfo[j].tokenAddress).balanceOf(fundsHolder) * oldAmount) /
                    _totalShares;

                totalSharesOfERC20[id][prizeInfo[j].tokenAddress] = _totalShares - oldAmount;
            }
            FundsHolder(fundsHolder).withdrawToken(prizeInfo[j], msg.sender);
        }
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
