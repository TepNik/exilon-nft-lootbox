// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.11;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "./pancake-swap/interfaces/IPancakeRouter02.sol";

import "./ExilonNftLootboxLibrary.sol";
import "./FeesCalculator.sol";

contract NftMarketplace is FeesCalculator, ReentrancyGuard {
    using EnumerableSet for EnumerableSet.UintSet;

    struct SellingInfo {
        ExilonNftLootboxLibrary.TokenInfo tokenInfo;
        uint256 price;
        address seller;
    }

    // public

    uint256 public feePercentage = 1_000; // 10%

    mapping(uint256 => SellingInfo) public idToSellingInfo;

    // private

    uint256 _lastId;

    EnumerableSet.UintSet private _activeIds;

    event SellCreated(
        address indexed user,
        uint256 sellPrice,
        uint256 id,
        ExilonNftLootboxLibrary.TokenInfo tokenInfo
    );
    event SellCanceled(address indexed user, uint256 id);
    event SellMaded(
        address indexed seller,
        address indexed buyer,
        uint256 id,
        uint256 usdPrice,
        uint256 bnbPrice,
        ExilonNftLootboxLibrary.TokenInfo tokenInfo
    );

    event FeePercentageChange(uint256 newValue);

    constructor(
        address _usdToken,
        IPancakeRouter02 _pancakeRouter,
        address _feeReceiver
    ) FeesCalculator(_usdToken, _pancakeRouter, _feeReceiver) {
        emit FeePercentageChange(feePercentage);
    }

    function sellToken(ExilonNftLootboxLibrary.TokenInfo memory tokenInfo, uint256 sellPrice)
        external
        nonReentrant
        onlyEOA
    {
        require(
            tokenInfo.tokenType == ExilonNftLootboxLibrary.TokenType.ERC721 ||
                tokenInfo.tokenType == ExilonNftLootboxLibrary.TokenType.ERC1155,
            "NftMarketplace: Wrong token type"
        );
        if (tokenInfo.tokenType == ExilonNftLootboxLibrary.TokenType.ERC721) {
            require(tokenInfo.amount == 0, "NftMarketplace: Wring amount");

            require(
                IERC165(tokenInfo.tokenAddress).supportsInterface(bytes4(0x80ac58cd)),
                "NftMarketplace: ERC721 type"
            );
        } else {
            require(tokenInfo.amount > 0, "NftMarketplace: Wring amount");

            require(
                IERC165(tokenInfo.tokenAddress).supportsInterface(bytes4(0xd9b67a26)),
                "NftMarketplace: ERC1155 type"
            );
        }
        require(sellPrice > 0, "NftMarketplace: Wrong price");

        ExilonNftLootboxLibrary.withdrawToken(tokenInfo, msg.sender, address(this), true);

        uint256 __lastId = _lastId;
        _lastId = __lastId + 1;

        SellingInfo memory sellingInfo;
        sellingInfo.tokenInfo = tokenInfo;
        sellingInfo.price = sellPrice;
        sellingInfo.seller = msg.sender;

        idToSellingInfo[__lastId] = sellingInfo;

        _activeIds.add(__lastId);

        emit SellCreated(msg.sender, sellPrice, __lastId, tokenInfo);
    }

    function buy(uint256 id) external payable nonReentrant onlyEOA {
        require(_activeIds.contains(id), "NftMarketplace: Not active id");

        SellingInfo memory sellingInfo = idToSellingInfo[id];

        uint256 bnbValue = _checkFees(sellingInfo.price);
        _processFeeTransfer(bnbValue, sellingInfo.seller);

        ExilonNftLootboxLibrary.withdrawToken(
            sellingInfo.tokenInfo,
            address(this),
            msg.sender,
            true
        );

        _activeIds.remove(id);
        delete idToSellingInfo[id];

        emit SellMaded(
            sellingInfo.seller,
            msg.sender,
            id,
            sellingInfo.price,
            bnbValue,
            sellingInfo.tokenInfo
        );
    }

    function cancelSell(uint256 id) external nonReentrant {
        require(_activeIds.contains(id), "NftMarketplace: Not active id");

        SellingInfo memory sellingInfo = idToSellingInfo[id];

        require(msg.sender == sellingInfo.seller, "NftMarketplace: Not seller");

        _activeIds.remove(id);
        delete idToSellingInfo[id];

        ExilonNftLootboxLibrary.withdrawToken(
            sellingInfo.tokenInfo,
            address(this),
            msg.sender,
            true
        );

        emit SellCanceled(msg.sender, id);
    }

    function setFeePercentage(uint256 newValue) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newValue <= 5_000, "NftMarketplace: Too big percentage");
        feePercentage = newValue;

        emit FeePercentageChange(newValue);
    }

    function getBnbPriceToBuy(uint256 id) external view returns (uint256) {
        return _getBnbAmountToFront(idToSellingInfo[id].price);
    }

    function activeIdsLength() external view returns (uint256) {
        return _activeIds.length();
    }

    function activeIdsContains(uint256 id) external view returns (bool) {
        return _activeIds.contains(id);
    }

    function activeIdsAt(uint256 index) external view returns (uint256) {
        return _activeIds.at(index);
    }

    function _processFeeTransfer(uint256 bnbAmount, address to) private {
        uint256 amountToSeller = (bnbAmount * (10_000 - feePercentage)) / 10_000;

        // seller is not a contract and shouldn't fail
        (bool success, ) = to.call{value: amountToSeller}("");
        require(success, "NftMarketplace: Transfer to seller");

        _processFeeTransferOnFeeReceiver();
    }
}
