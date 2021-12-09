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
    uint256 public addingPrizesPrice;
    uint256 public minimumOpeningPrice;
    mapping(uint256 => uint256) public openingPrice;
    uint256 public creatorPercentage = 5000; // 50%

    uint256 public amountOfExilonToOpenner;

    // addresses info
    IERC20 public immutable exilon;
    address public immutable usdToken;
    address public immutable masterContract;

    // private

    uint256 private _lastId;
    mapping(uint256 => string) private _idsToUri;
    uint256 private _nonce;
    mapping(address => EnumerableSet.UintSet) private _idsUsersHold;

    event LootboxMaded(
        address indexed maker,
        uint256 id,
        uint256 openingPrice,
        address indexed fundsHolder
    );
    event WithdrawLootbox(address indexed maker, uint256 id, uint256 openingPrice);
    event IdDeleted(uint256 id, address indexed fundsHolder);

    event PriceChanges(
        uint256 newCreatingPrice,
        uint256 newAddingPrizesPrice,
        uint256 newMinimumOpeningPrice,
        uint256 newCreatorPercentage
    );
    event OpeningPriceForIdChanged(uint256 id, uint256 newOpeningPrice);
    event ChangeAmountOfExilonToOpenner(uint256 newValue);
    event BadExilonTransfer(address indexed to, uint256 amount);

    constructor(IERC20 _exilon, address _usdToken) ERC1155("") {
        exilon = _exilon;
        amountOfExilonToOpenner = 10**IERC20Metadata(address(_exilon)).decimals(); // One Exilon Token

        usdToken = _usdToken;
        uint256 oneDollar = 10**IERC20Metadata(_usdToken).decimals();
        minimumOpeningPrice = oneDollar;
        creatingPrice = oneDollar;
        addingPrizesPrice = oneDollar;

        FundsHolder _masterContract = new FundsHolder();
        _masterContract.init();
        masterContract = address(_masterContract);

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
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

        // collect fees for creating
        {
            uint256 _creatingPrice = creatingPrice;
            if (_creatingPrice > 0) {
                IERC20(usdToken).safeTransferFrom(msg.sender, address(this), _creatingPrice);
            }
        }

        // get total information about tokens in all winningPlaces
        (
            ExilonNftLootboxLibrary.TokenInfo[] memory allTokensInfo,
            uint256 amountOfLootBoxes
        ) = ExilonNftLootboxLibrary.processTokensInfo(winningPlaces);

        uint256 lastId = _lastId;
        if (onMarket) {
            _mint(address(this), lastId, amountOfLootBoxes, "");
        } else {
            _mint(msg.sender, lastId, amountOfLootBoxes, "");
        }
        _lastId = lastId + 1;

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

        emit LootboxMaded(msg.sender, lastId, _openingPrice, address(fundsHolder));
    }

    function withdrawPrize(uint256 id, uint256 amount) external {
        _withdrawPrize(msg.sender, id, amount);
    }

    function buyId(uint256 id, uint256 amount) external {
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

    function withdrawCommissions() external onlyRole(DEFAULT_ADMIN_ROLE) nonReentrant {
        uint256 balance = IERC20(usdToken).balanceOf(address(this));
        if (balance > 0) {
            IERC20(usdToken).safeTransfer(msg.sender, balance);
        }
    }

    function setPriceInfo(
        uint256 _creatingPrice,
        uint256 _addingPrizesPrice,
        uint256 _minimumOpeningPrice,
        uint256 _creatorPercentage
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_creatorPercentage <= 10000, "ExilonNftLootbox: Too big percentage");

        creatingPrice = _creatingPrice;
        addingPrizesPrice = _addingPrizesPrice;
        minimumOpeningPrice = _minimumOpeningPrice;
        creatorPercentage = _creatorPercentage;

        emit PriceChanges(
            _creatingPrice,
            _addingPrizesPrice,
            _minimumOpeningPrice,
            _creatorPercentage
        );
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

    function uri(uint256 id) public view virtual override returns (string memory) {
        return _idsToUri[id];
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
        _burn(redeemer, id, amount);

        uint256 totalFee = _collectFeesFromOpening(id);

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

            uint256 winningIndex = _getWinningIndex(_prizes, randomNumber);

            _withdrawWinningPlace(_prizes[winningIndex].prizesInfo, id, _fundsHolder);

            _prizes = _removeWinningPlace(_prizes, id, winningIndex);
        }
        lootxesAmount[id] = restLootboxes;
        _nonce = nonce;

        if (restLootboxes == 0) {
            _deleteId(id, _fundsHolder);
        }

        emit WithdrawLootbox(msg.sender, id, totalFee);
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

    function _collectFeesFromOpening(uint256 id) private returns (uint256) {
        uint256 totalFee = openingPrice[id];
        if (totalFee > 0) {
            uint256 feeToCreator = (totalFee * creatorPercentage) / 10000;
            if (feeToCreator > 0) {
                IERC20(usdToken).safeTransferFrom(msg.sender, idsToCreator[id], feeToCreator);
            }
            IERC20(usdToken).safeTransferFrom(msg.sender, address(this), totalFee - feeToCreator);
        }
        return totalFee;
    }

    function _sendExilonToOpenner() private {
        uint256 _amountOfExilonToOpenner = amountOfExilonToOpenner;
        if (_amountOfExilonToOpenner > 0) {
            (bool success, ) = address(exilon).call(
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
        }
        FundsHolder(fundsHolder).withdrawTokens(prizeInfo, msg.sender);
    }

    function _getWinningIndex(
        ExilonNftLootboxLibrary.WinningPlace[] memory restPrizes,
        uint256 randomNumber
    ) private pure returns (uint256 winningIndex) {
        winningIndex = type(uint256).max;
        uint256 amountPassed;
        for (uint256 j = 0; j < restPrizes.length && winningIndex == type(uint256).max; ++j) {
            if (restPrizes[j].placeAmounts >= randomNumber + 1 - amountPassed) {
                winningIndex = j;
            }
            amountPassed += restPrizes[j].placeAmounts;
        }
        require(winningIndex != type(uint256).max, "ExilonNftLootbox: Random generator");
    }

    function _removeWinningPlace(
        ExilonNftLootboxLibrary.WinningPlace[] memory restPrizes,
        uint256 id,
        uint256 winningIndex
    ) private returns (ExilonNftLootboxLibrary.WinningPlace[] memory) {
        restPrizes[winningIndex].placeAmounts -= 1;
        prizes[id][winningIndex].placeAmounts -= 1;
        if (restPrizes[winningIndex].placeAmounts == 0) {
            uint256 len = restPrizes.length;
            if (winningIndex < len - 1) {
                prizes[id][winningIndex] = prizes[id][len - 1];
                restPrizes[winningIndex] = restPrizes[len - 1];
            }

            prizes[id].pop();

            assembly {
                mstore(restPrizes, sub(mload(restPrizes), 1))
            }
        }

        return restPrizes;
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
