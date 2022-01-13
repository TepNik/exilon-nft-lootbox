// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.11;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "./pancake-swap/interfaces/IPancakeRouter02.sol";

import "./ExilonNftLootboxLibrary.sol";
import "./FeesCalculator.sol";

contract NftMarketplace is FeesCalculator {
    using EnumerableSet for EnumerableSet.UintSet;

    struct SellingInfo {
        ExilonNftLootboxLibrary.TokenInfo tokenInfo;
        uint256 price;
        address seller;
    }

    struct ModerationInfo {
        ExilonNftLootboxLibrary.TokenInfo tokenInfo;
        address requestingAddress;
    }

    struct TokenStateInfo {
        uint256 price;
        uint256 duration;
    }

    // public

    uint256 public moderationPrice;
    uint256 public feePercentage = 1_000; // 10%

    mapping(uint256 => SellingInfo) public idToSellingInfo;

    mapping(address => mapping(uint256 => bool)) public isTokenModerated;
    mapping(address => mapping(uint256 => bool)) public isOnModeration;

    uint256 public constant NUMBER_OF_STATES = 20;
    TokenStateInfo[NUMBER_OF_STATES] public tokenStateInfo;

    // private

    uint256 private _lastIdForSellingInfo;

    EnumerableSet.UintSet private _activeIds;
    mapping(address => EnumerableSet.UintSet) private _userToActiveIds;

    ModerationInfo[] private _moderationRequests;

    mapping(address => mapping(uint256 => uint256)) private _moderatedTokenId;
    ExilonNftLootboxLibrary.TokenInfo[] private _moderatedTokens;

    mapping(address => mapping(uint256 => uint256[NUMBER_OF_STATES])) private _tokenStates;

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

    event ModerationRequest(address indexed user, ExilonNftLootboxLibrary.TokenInfo tokenInfo);
    event ModerationPass(ExilonNftLootboxLibrary.TokenInfo tokenInfo);
    event ModerationFail(ExilonNftLootboxLibrary.TokenInfo tokenInfo);
    event ModerationCanceled(ExilonNftLootboxLibrary.TokenInfo tokenInfo);

    event StateInfoChange(uint256 stateNum, uint256 price, uint256 duration);
    event BuyTokenState(ExilonNftLootboxLibrary.TokenInfo tokenInfo, uint256 stateNum);

    event FeePercentageChange(uint256 newValue);
    event ModerationPriceChange(uint256 newValue);

    constructor(
        address _usdToken,
        IPancakeRouter02 _pancakeRouter,
        address _feeReceiver
    ) FeesCalculator(_usdToken, _pancakeRouter, _feeReceiver) {
        moderationPrice = _oneUsd;

        emit FeePercentageChange(feePercentage);
        emit ModerationPriceChange(_oneUsd);
    }

    function sellToken(ExilonNftLootboxLibrary.TokenInfo calldata tokenInfo, uint256 sellPrice)
        external
        nonReentrant
        onlyEOA
    {
        _checkInputData(tokenInfo);
        require(sellPrice > 0, "NftMarketplace: Wrong price");

        ExilonNftLootboxLibrary.withdrawToken(tokenInfo, msg.sender, address(this), true);

        uint256 __lastId = _lastIdForSellingInfo;
        _lastIdForSellingInfo = __lastId + 1;

        SellingInfo memory sellingInfo;
        sellingInfo.tokenInfo = tokenInfo;
        sellingInfo.price = sellPrice;
        sellingInfo.seller = msg.sender;

        idToSellingInfo[__lastId] = sellingInfo;
        _userToActiveIds[msg.sender].add(__lastId);

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
        _userToActiveIds[sellingInfo.seller].remove(id);
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
        _userToActiveIds[msg.sender].remove(id);
        delete idToSellingInfo[id];

        ExilonNftLootboxLibrary.withdrawToken(
            sellingInfo.tokenInfo,
            address(this),
            msg.sender,
            true
        );

        emit SellCanceled(msg.sender, id);
    }

    function sendAddressOnModeration(ExilonNftLootboxLibrary.TokenInfo calldata tokenInfo)
        external
        payable
        nonReentrant
        onlyEOA
    {
        _checkInputData(tokenInfo);
        require(
            isTokenModerated[tokenInfo.tokenAddress][tokenInfo.id] == false,
            "NftMarketplace: Moderated"
        );
        require(
            isOnModeration[tokenInfo.tokenAddress][tokenInfo.id] == false,
            "NftMarketplace: Moderating"
        );

        _checkFees(moderationPrice);
        _processFeeTransferOnFeeReceiver();

        _moderationRequests.push(
            ModerationInfo({tokenInfo: tokenInfo, requestingAddress: msg.sender})
        );

        emit ModerationRequest(msg.sender, tokenInfo);
    }

    function buyTokenState(ExilonNftLootboxLibrary.TokenInfo calldata tokenInfo, uint256 stateNum)
        external
        payable
        nonReentrant
        onlyEOA
    {
        require(stateNum < NUMBER_OF_STATES, "NftMarketplace: State number");
        _checkInputData(tokenInfo);

        uint256 price = tokenStateInfo[stateNum].price;
        require(price > 0, "NftMarketplace: Not opened state");
        _checkFees(price);
        _processFeeTransferOnFeeReceiver();

        _tokenStates[tokenInfo.tokenAddress][tokenInfo.id][stateNum] = block.timestamp;

        emit BuyTokenState(tokenInfo, stateNum);
    }

    function processModeration(uint256 id, bool decision) external onlyManagerOrAdmin {
        uint256 length = _moderationRequests.length;
        require(id < length, "NftMarketplace: Not active id");

        ModerationInfo memory moderationInfo = _moderationRequests[id];

        if (id < length - 1) {
            _moderationRequests[id] = _moderationRequests[length - 1];
        }
        _moderationRequests.pop();
        delete isOnModeration[moderationInfo.tokenInfo.tokenAddress][moderationInfo.tokenInfo.id];

        if (decision) {
            isTokenModerated[moderationInfo.tokenInfo.tokenAddress][
                moderationInfo.tokenInfo.id
            ] = true;

            _moderatedTokens.push();
            _moderatedTokenId[moderationInfo.tokenInfo.tokenAddress][moderationInfo.tokenInfo.id] =
                _moderatedTokens.length -
                1;

            emit ModerationPass(moderationInfo.tokenInfo);
        } else {
            emit ModerationFail(moderationInfo.tokenInfo);
        }
    }

    function cancelModeration(ExilonNftLootboxLibrary.TokenInfo calldata tokenInfo)
        external
        onlyManagerOrAdmin
    {
        _checkInputData(tokenInfo);

        bool isModerated = isTokenModerated[tokenInfo.tokenAddress][tokenInfo.id];
        if (isModerated) {
            delete isTokenModerated[tokenInfo.tokenAddress][tokenInfo.id];

            uint256 indexDeleting = _moderatedTokenId[tokenInfo.tokenAddress][tokenInfo.id];
            uint256 length = _moderatedTokens.length;
            if (indexDeleting < length - 1) {}
            _moderatedTokens.pop();

            for (uint256 i = 0; i < NUMBER_OF_STATES; ++i) {
                delete _tokenStates[tokenInfo.tokenAddress][tokenInfo.id][i];
            }

            emit ModerationCanceled(tokenInfo);
        }
    }

    function setStateInfo(
        uint256 stateNum,
        uint256 price,
        uint256 duration
    ) external onlyManagerOrAdmin {
        require(stateNum < NUMBER_OF_STATES, "NftMarketplace: State number");
        require(price > 0, "NftMarketplace: Wrong price");

        tokenStateInfo[stateNum] = TokenStateInfo({price: price, duration: duration});

        emit StateInfoChange(stateNum, price, duration);
    }

    function setFeePercentage(uint256 newValue) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newValue <= 5_000, "NftMarketplace: Too big percentage");
        feePercentage = newValue;

        emit FeePercentageChange(newValue);
    }

    function setModerationPrice(uint256 newValue) external onlyRole(DEFAULT_ADMIN_ROLE) {
        moderationPrice = newValue;

        emit ModerationPriceChange(newValue);
    }

    function getBnbPriceToBuy(uint256 id) external view returns (uint256) {
        return _getBnbAmountToFront(idToSellingInfo[id].price);
    }

    function getBnbPriceForModeration() external view returns (uint256) {
        return _getBnbAmountToFront(moderationPrice);
    }

    function activeIdsLength() external view returns (uint256) {
        return _activeIds.length();
    }

    function activeIdsAt(uint256 index) external view returns (uint256) {
        return _activeIds.at(index);
    }

    function userToActiveIdsLength(address user) external view returns (uint256) {
        return _userToActiveIds[user].length();
    }

    function userToActiveIdsAt(address user, uint256 index) external view returns (uint256) {
        return _userToActiveIds[user].at(index);
    }

    function moderationRequestsLen() external view returns (uint256) {
        return _moderationRequests.length;
    }

    function moderationRequestsIndex(uint256 indexFrom, uint256 indexTo)
        external
        view
        returns (ModerationInfo[] memory result)
    {
        uint256 fullLength = _moderationRequests.length;
        if (indexFrom > indexTo || indexTo > fullLength || indexTo - indexFrom > fullLength) {
            return result;
        }

        result = new ModerationInfo[](indexTo - indexFrom);
        for (uint256 i = indexFrom; i < indexTo; ++i) {
            result[i - indexFrom] = _moderationRequests[i];
        }
    }

    function getTokenStates(ExilonNftLootboxLibrary.TokenInfo calldata tokenInfo)
        external
        view
        returns (bool[NUMBER_OF_STATES] memory result)
    {
        for (uint256 i = 0; i < NUMBER_OF_STATES; ++i) {
            result[i] =
                _tokenStates[tokenInfo.tokenAddress][tokenInfo.id][i] +
                    tokenStateInfo[i].duration >=
                block.timestamp;
        }
    }

    function _processFeeTransfer(uint256 bnbAmount, address to) private {
        uint256 amountToSeller = (bnbAmount * (10_000 - feePercentage)) / 10_000;

        // seller is not a contract and shouldn't fail
        (bool success, ) = to.call{value: amountToSeller}("");
        require(success, "NftMarketplace: Transfer to seller");

        _processFeeTransferOnFeeReceiver();
    }

    function _checkInputData(ExilonNftLootboxLibrary.TokenInfo calldata tokenInfo) private view {
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
    }
}
