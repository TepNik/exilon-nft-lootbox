// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.12;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/utils/Address.sol";

import "./pancake-swap/interfaces/IPancakeRouter02.sol";

import "./ExilonNftLootboxLibrary.sol";
import "./FeeCalculator.sol";
import "./FeeSender.sol";

import "./interfaces/INftMarketplace.sol";
import "./interfaces/IExilonNftLootboxMain.sol";

contract NftMarketplace is FeeCalculator, FeeSender, ERC721Holder, ERC1155Holder, INftMarketplace {
    using EnumerableSet for EnumerableSet.UintSet;
    using Address for address;

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
        uint256 changeTime;
        bool zeroPrevious;
    }

    // public

    IExilonNftLootboxMain public exilonNftLootboxMain;

    uint256 public moderationPrice;
    uint256 public feePercentage = 200; // 2%

    mapping(uint256 => SellingInfo) public idToSellingInfo;

    mapping(address => mapping(uint256 => bool)) public override isTokenModerated;
    mapping(address => mapping(uint256 => bool)) public isOnModeration;

    uint256 public constant NUMBER_OF_STATES = 20;
    TokenStateInfo[NUMBER_OF_STATES] public tokenStateInfo;

    // private

    uint256 private _lastIdForSellingInfo;

    EnumerableSet.UintSet private _activeIds;
    mapping(address => EnumerableSet.UintSet) private _userToActiveIds;

    ModerationInfo[] private _moderationRequests;
    mapping(address => mapping(uint256 => uint256)) private _moderationRequestId;

    mapping(address => mapping(uint256 => uint256)) private _moderatedTokenId;
    ExilonNftLootboxLibrary.TokenInfo[] private _moderatedTokens;

    mapping(address => mapping(uint256 => uint256[NUMBER_OF_STATES])) private _tokenStates;

    event SellCreated(
        address indexed user,
        uint256 sellPrice,
        uint256 sellPriceBnb,
        uint256 id,
        ExilonNftLootboxLibrary.TokenInfo tokenInfo
    );
    event SellCanceled(
        address indexed user,
        uint256 id,
        ExilonNftLootboxLibrary.TokenInfo tokenInfo
    );
    event SellMaded(
        address indexed seller,
        address indexed buyer,
        uint256 id,
        uint256 usdPrice,
        uint256 bnbPrice,
        uint256 timestamp,
        ExilonNftLootboxLibrary.TokenInfo tokenInfo
    );

    event ModerationRequest(address indexed user, ExilonNftLootboxLibrary.TokenInfo tokenInfo);
    event ModerationPass(
        address indexed manager,
        address indexed requester,
        ExilonNftLootboxLibrary.TokenInfo tokenInfo
    );
    event ModerationFail(
        address indexed manager,
        address indexed requester,
        ExilonNftLootboxLibrary.TokenInfo tokenInfo
    );
    event ModerationCanceled(address indexed manager, ExilonNftLootboxLibrary.TokenInfo tokenInfo);

    event StateInfoChange(
        uint256 stateNum,
        uint256 price,
        uint256 duration,
        uint256 timestamp,
        bool zeroPrevious
    );
    event BuyTokenState(ExilonNftLootboxLibrary.TokenInfo tokenInfo, uint256 stateNum);

    event FeePercentageChange(uint256 newValue);
    event ModerationPriceChange(uint256 newValue);

    constructor(
        address _usdToken,
        IPancakeRouter02 _pancakeRouter,
        address _feeReceiver,
        IAccess _accessControl
    )
        FeeCalculator(_usdToken, _pancakeRouter)
        FeeSender(_feeReceiver)
        AccessConnector(_accessControl)
    {
        moderationPrice = 5 * _oneUsd;

        emit FeePercentageChange(feePercentage);
        emit ModerationPriceChange(_oneUsd);
    }

    function init() external {
        require(address(exilonNftLootboxMain) == address(0), "NftMarketplace: Already inited");

        exilonNftLootboxMain = IExilonNftLootboxMain(msg.sender);
    }

    function sellToken(ExilonNftLootboxLibrary.TokenInfo calldata tokenInfo, uint256 sellPrice)
        external
        nonReentrant
        onlyEOA
    {
        _checkInputData(tokenInfo, false);
        require(sellPrice > 0, "NftMarketplace: Wrong price");

        ExilonNftLootboxLibrary.withdrawToken(tokenInfo, msg.sender, address(this), true);

        uint256 __lastId = _lastIdForSellingInfo++;

        SellingInfo memory sellingInfo;
        sellingInfo.tokenInfo = tokenInfo;
        sellingInfo.price = sellPrice;
        sellingInfo.seller = msg.sender;

        idToSellingInfo[__lastId] = sellingInfo;
        _userToActiveIds[msg.sender].add(__lastId);

        _activeIds.add(__lastId);

        emit SellCreated(msg.sender, sellPrice, _getBnbAmount(sellPrice), __lastId, tokenInfo);
    }

    function buy(uint256 id, uint256 amount) external payable nonReentrant onlyEOA {
        require(_activeIds.contains(id), "NftMarketplace: Not active id");

        SellingInfo memory sellingInfo = idToSellingInfo[id];

        uint256 amountBefore = sellingInfo.tokenInfo.amount;
        if (sellingInfo.tokenInfo.tokenType == ExilonNftLootboxLibrary.TokenType.ERC721) {
            require(amount == 0, "NftMarketplace: ERC721 amount");
        } else {
            require(amount > 0 && amount <= amountBefore, "NftMarketplace: ERC1155 amount");
        }

        uint256 bnbValue = _checkFees(sellingInfo.price * amount);
        _processFeeTransfer(bnbValue, sellingInfo.seller);

        sellingInfo.tokenInfo.amount = amount;
        ExilonNftLootboxLibrary.withdrawToken(
            sellingInfo.tokenInfo,
            address(this),
            msg.sender,
            true
        );

        if (amountBefore - amount == 0) {
            _activeIds.remove(id);
            _userToActiveIds[sellingInfo.seller].remove(id);
            delete idToSellingInfo[id];
        } else {
            idToSellingInfo[id].tokenInfo.amount = amountBefore - amount;
        }

        emit SellMaded(
            sellingInfo.seller,
            msg.sender,
            id,
            sellingInfo.price,
            bnbValue,
            block.timestamp,
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

        emit SellCanceled(msg.sender, id, sellingInfo.tokenInfo);
    }

    function sendAddressOnModeration(ExilonNftLootboxLibrary.TokenInfo calldata tokenInfo)
        external
        payable
        nonReentrant
        onlyEOA
    {
        _checkInputData(tokenInfo, true);
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
        _moderationRequestId[tokenInfo.tokenAddress][tokenInfo.id] = _moderationRequests.length - 1;
        isOnModeration[tokenInfo.tokenAddress][tokenInfo.id] = true;

        emit ModerationRequest(msg.sender, tokenInfo);
    }

    function buyTokenState(ExilonNftLootboxLibrary.TokenInfo calldata tokenInfo, uint256 stateNum)
        external
        payable
        nonReentrant
        onlyEOA
    {
        require(stateNum < NUMBER_OF_STATES, "NftMarketplace: State number");
        _checkInputData(tokenInfo, true);

        uint256 price = tokenStateInfo[stateNum].price;
        require(price > 0, "NftMarketplace: Not opened state");
        _checkFees(price);
        _processFeeTransferOnFeeReceiver();

        _tokenStates[tokenInfo.tokenAddress][tokenInfo.id][stateNum] = block.timestamp;

        emit BuyTokenState(tokenInfo, stateNum);
    }

    function processModeration(
        address tokenAddress,
        uint256 tokenId,
        bool decision
    ) external onlyManagerOrAdmin {
        require(isOnModeration[tokenAddress][tokenId], "NftMarketplace: Not on moderation");
        delete isOnModeration[tokenAddress][tokenId];

        uint256 moderationRequestsIndex = _moderationRequestId[tokenAddress][tokenId];
        delete _moderationRequestId[tokenAddress][tokenId];

        ModerationInfo memory moderationInfo = _moderationRequests[moderationRequestsIndex];

        uint256 moderationRequestsLength = _moderationRequests.length;
        if (moderationRequestsIndex < moderationRequestsLength - 1) {
            ModerationInfo memory replacement = _moderationRequests[moderationRequestsLength - 1];
            _moderationRequests[moderationRequestsIndex] = replacement;

            _moderationRequestId[replacement.tokenInfo.tokenAddress][
                replacement.tokenInfo.id
            ] = moderationRequestsIndex;
        }
        _moderationRequests.pop();

        if (decision) {
            isTokenModerated[moderationInfo.tokenInfo.tokenAddress][
                moderationInfo.tokenInfo.id
            ] = true;

            _moderatedTokens.push(moderationInfo.tokenInfo);
            _moderatedTokenId[moderationInfo.tokenInfo.tokenAddress][moderationInfo.tokenInfo.id] =
                _moderatedTokens.length -
                1;

            emit ModerationPass(
                msg.sender,
                moderationInfo.requestingAddress,
                moderationInfo.tokenInfo
            );
        } else {
            emit ModerationFail(
                msg.sender,
                moderationInfo.requestingAddress,
                moderationInfo.tokenInfo
            );
        }
    }

    function cancelModeration(ExilonNftLootboxLibrary.TokenInfo calldata tokenInfo)
        external
        onlyManagerOrAdmin
    {
        _checkInputData(tokenInfo, true);
        bool isModerated = isTokenModerated[tokenInfo.tokenAddress][tokenInfo.id];
        if (isModerated) {
            delete isTokenModerated[tokenInfo.tokenAddress][tokenInfo.id];

            uint256 indexDeleting = _moderatedTokenId[tokenInfo.tokenAddress][tokenInfo.id];
            delete _moderatedTokenId[tokenInfo.tokenAddress][tokenInfo.id];

            uint256 length = _moderatedTokens.length;
            if (indexDeleting < length - 1) {
                ExilonNftLootboxLibrary.TokenInfo memory replacement = _moderatedTokens[length - 1];
                _moderatedTokens[indexDeleting] = replacement;

                _moderatedTokenId[replacement.tokenAddress][replacement.id] = indexDeleting;
            }
            _moderatedTokens.pop();

            for (uint256 i = 0; i < NUMBER_OF_STATES; ++i) {
                delete _tokenStates[tokenInfo.tokenAddress][tokenInfo.id][i];
            }

            IExilonNftLootboxMain _exilonNftLootboxMain = exilonNftLootboxMain;
            if (
                tokenInfo.tokenAddress == address(_exilonNftLootboxMain) &&
                _exilonNftLootboxMain.isMerging(tokenInfo.id)
            ) {
                _exilonNftLootboxMain.cancelMergeRequest(tokenInfo.id);
            }

            emit ModerationCanceled(msg.sender, tokenInfo);
        }
    }

    function setStateInfo(
        uint256 stateNum,
        uint256 price,
        uint256 duration,
        bool zeroPrevious
    ) external onlyAdmin {
        require(stateNum < NUMBER_OF_STATES, "NftMarketplace: State number");

        if (price == 0) {
            require(duration == 0 && zeroPrevious == false, "NftMarketplace: Wrong usage");
        }

        tokenStateInfo[stateNum] = TokenStateInfo({
            price: price,
            duration: duration,
            changeTime: block.timestamp,
            zeroPrevious: zeroPrevious
        });

        emit StateInfoChange(stateNum, price, duration, block.timestamp, zeroPrevious);
    }

    function setFeePercentage(uint256 newValue) external onlyAdmin {
        require(newValue <= 5_000, "NftMarketplace: Too big percentage");
        feePercentage = newValue;

        emit FeePercentageChange(newValue);
    }

    function setModerationPrice(uint256 newValue) external onlyAdmin {
        moderationPrice = newValue;

        emit ModerationPriceChange(newValue);
    }

    function getBnbPriceToBuy(uint256 id, uint256 amount) external view returns (uint256) {
        if (idToSellingInfo[id].tokenInfo.tokenType == ExilonNftLootboxLibrary.TokenType.ERC721) {
            return _getBnbAmountToFront(idToSellingInfo[id].price);
        } else {
            return _getBnbAmountToFront(idToSellingInfo[id].price * amount);
        }
    }

    function getBnbPriceForModeration() external view returns (uint256) {
        return _getBnbAmountToFront(moderationPrice);
    }

    function getBnbPriceForState(uint256 state) external view returns (uint256) {
        if (state >= NUMBER_OF_STATES) {
            return 0;
        }
        return _getBnbAmountToFront(tokenStateInfo[state].price);
    }

    function activeIdsLength() external view returns (uint256) {
        return _activeIds.length();
    }

    function activeIds(uint256 indexFrom, uint256 indexTo)
        external
        view
        returns (uint256[] memory result)
    {
        uint256 fullLength = _activeIds.length();
        if (indexFrom >= indexTo || indexTo > fullLength) {
            return result;
        }

        result = new uint256[](indexTo - indexFrom);
        for (uint256 i = indexFrom; i < indexTo; ++i) {
            result[i - indexFrom] = _activeIds.at(i);
        }
    }

    function userToActiveIdsLength(address user) external view returns (uint256) {
        return _userToActiveIds[user].length();
    }

    function userToActiveIdsAt(
        address user,
        uint256 indexFrom,
        uint256 indexTo
    ) external view returns (uint256[] memory result) {
        uint256 fullLength = _userToActiveIds[user].length();
        if (indexFrom >= indexTo || indexTo > fullLength) {
            return result;
        }

        result = new uint256[](indexTo - indexFrom);
        for (uint256 i = indexFrom; i < indexTo; ++i) {
            result[i - indexFrom] = _userToActiveIds[user].at(i);
        }
    }

    function moderationRequestsLen() external view returns (uint256) {
        return _moderationRequests.length;
    }

    function moderationRequests(uint256 indexFrom, uint256 indexTo)
        external
        view
        returns (ModerationInfo[] memory result)
    {
        uint256 fullLength = _moderationRequests.length;
        if (indexFrom >= indexTo || indexTo > fullLength) {
            return result;
        }

        result = new ModerationInfo[](indexTo - indexFrom);
        for (uint256 i = indexFrom; i < indexTo; ++i) {
            result[i - indexFrom] = _moderationRequests[i];
        }
    }

    function moderatedTokensLen() external view returns (uint256) {
        return _moderatedTokens.length;
    }

    function moderatedTokens(uint256 indexFrom, uint256 indexTo)
        external
        view
        returns (ExilonNftLootboxLibrary.TokenInfo[] memory result)
    {
        uint256 fullLength = _moderatedTokens.length;
        if (indexFrom >= indexTo || indexTo > fullLength) {
            return result;
        }

        result = new ExilonNftLootboxLibrary.TokenInfo[](indexTo - indexFrom);
        for (uint256 i = indexFrom; i < indexTo; ++i) {
            result[i - indexFrom] = _moderatedTokens[i];
        }
    }

    function getTokenStates(ExilonNftLootboxLibrary.TokenInfo[] calldata tokenInfo)
        external
        view
        returns (bool[NUMBER_OF_STATES][] memory result)
    {
        result = new bool[NUMBER_OF_STATES][](tokenInfo.length);
        for (uint256 i = 0; i < tokenInfo.length; ++i) {
            for (uint256 state = 0; state < NUMBER_OF_STATES; ++state) {
                TokenStateInfo memory _tokenStateInfo = tokenStateInfo[state];

                uint256 tokenState = _tokenStates[tokenInfo[i].tokenAddress][tokenInfo[i].id][
                    state
                ];

                if (
                    (_tokenStateInfo.zeroPrevious && tokenState < _tokenStateInfo.changeTime) ||
                    tokenState == 0
                ) {
                    result[i][state] = false;
                } else {
                    result[i][state] = tokenState + _tokenStateInfo.duration >= block.timestamp;
                }
            }
        }
    }

    function _processFeeTransfer(uint256 bnbAmount, address to) private {
        uint256 amountToSeller = (bnbAmount * (10_000 - feePercentage)) / 10_000;

        // seller is not a contract and shouldn't fail
        (bool success, ) = to.call{value: amountToSeller}("");
        require(success, "NftMarketplace: Transfer to seller");

        _processFeeTransferOnFeeReceiver();
    }

    function _checkInputData(
        ExilonNftLootboxLibrary.TokenInfo calldata tokenInfo,
        bool isZeroAmount
    ) private view {
        require(tokenInfo.tokenAddress.isContract(), "NftMarketplace: Not a contract");
        require(
            tokenInfo.tokenType == ExilonNftLootboxLibrary.TokenType.ERC721 ||
                tokenInfo.tokenType == ExilonNftLootboxLibrary.TokenType.ERC1155,
            "NftMarketplace: Wrong token type"
        );
        if (tokenInfo.tokenType == ExilonNftLootboxLibrary.TokenType.ERC721) {
            require(
                IERC165(tokenInfo.tokenAddress).supportsInterface(bytes4(0x80ac58cd)),
                "NftMarketplace: ERC721 type"
            );
            require(tokenInfo.amount == 0, "NftMarketplace: ERC721 amount");
        } else {
            require(
                IERC165(tokenInfo.tokenAddress).supportsInterface(bytes4(0xd9b67a26)),
                "NftMarketplace: ERC1155 type"
            );
            if (isZeroAmount) {
                require(tokenInfo.amount == 0, "NftMarketplace: Not zero amount");
            } else {
                require(tokenInfo.amount > 0, "NftMarketplace: Zero amount");
            }
        }
    }
}
