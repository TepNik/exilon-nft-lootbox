// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.11;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./pancake-swap/interfaces/IPancakeRouter02.sol";
import "./pancake-swap/interfaces/IPancakeFactory.sol";
import "./pancake-swap/interfaces/IPancakePair.sol";

import "./FeeCalculator.sol";
import "./FeeSender.sol";

import "./interfaces/IExilonNftLootboxMain.sol";
import "./interfaces/INftMarketplace.sol";
import "./interfaces/IExilonNftLootboxMaster.sol";
import "./interfaces/IPriceHolder.sol";

contract ExilonNftLootboxMain is ERC1155, FeeCalculator, FeeSender, IExilonNftLootboxMain {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.UintSet;

    struct MergeRequestInfo {
        uint256 id;
        uint256 megaId;
        address requestingAddress;
        uint256 refundPoolAmount;
    }

    // public

    IExilonNftLootboxMaster public masterContract;
    IPriceHolder public priceHolder;
    INftMarketplace public immutable nftMarketplace;

    uint256 public mergePrice;

    mapping(uint256 => ExilonNftLootboxLibrary.LootBoxType) public override lootboxType;
    mapping(uint256 => bool) public isMerging;

    mapping(uint256 => uint256) public override totalSupply;

    // private

    IPancakeFactory private immutable _pancakeFactory;

    mapping(address => EnumerableSet.UintSet) private _idsUsersHold;
    mapping(uint256 => string) private _idsToUri;

    MergeRequestInfo[] private _mergeRequestInfo;
    mapping(uint256 => uint256) private _idToMergeRequestIndex;
    mapping(uint256 => uint256) private _isMergingToCount;

    mapping(ExilonNftLootboxLibrary.LootBoxType => EnumerableSet.UintSet) private _lootBoxTypeToIds;

    modifier onlyMaster() {
        require(msg.sender == address(masterContract), "ExilonNftLootboxMain: Not master");
        _;
    }

    event RefundFundCollected(address indexed user, uint256 amount);
    event RefundPaid(
        address indexed user,
        address indexed creator,
        uint256 usdAmount,
        uint256 usdAmountCreator
    );

    event MegaLootbox(
        address indexed manager,
        address indexed requestingAddress,
        uint256 id,
        ExilonNftLootboxLibrary.LootBoxType lootboxType
    );
    event MergeRequest(address indexed user, uint256 id, uint256 megaId);
    event MergeSuccess(
        address indexed manager,
        address indexed requestingAddress,
        uint256 id,
        uint256 megaId
    );
    event MergeFail(
        address indexed manager,
        address indexed requestingAddress,
        uint256 id,
        uint256 megaId
    );
    event MergeCancel(address indexed requestingAddress, uint256 id, uint256 megaId);

    event MergePriceChange(uint256 newValue);

    constructor(
        INftMarketplace _nftMarketplace,
        address _usdToken,
        IPancakeRouter02 _pancakeRouter,
        address _feeReceiver,
        IAccess _accessControl
    )
        ERC1155("")
        FeeCalculator(_usdToken, _pancakeRouter)
        FeeSender(_feeReceiver)
        AccessConnector(_accessControl)
    {
        nftMarketplace = _nftMarketplace;
        _nftMarketplace.init();

        _pancakeFactory = IPancakeFactory(_pancakeRouter.factory());

        mergePrice = 100 * _oneUsd;

        emit MergePriceChange(_oneUsd);
    }

    function init(address _priceHolder) external override {
        require(
            address(masterContract) == address(0),
            "ExilonNftLootboxMain: Has already initialized"
        );
        masterContract = IExilonNftLootboxMaster(msg.sender);
        priceHolder = IPriceHolder(_priceHolder);
    }

    function requestIdForMerge(uint256 id, uint256 megaId) external payable nonReentrant onlyEOA {
        require(
            lootboxType[id] == ExilonNftLootboxLibrary.LootBoxType.DEFAULT,
            "ExilonNftLootboxMain: Default"
        );
        ExilonNftLootboxLibrary.LootBoxType megaType = lootboxType[megaId];
        require(
            megaType == ExilonNftLootboxLibrary.LootBoxType.MEGA_LOOTBOX_RESERVE ||
                megaType == ExilonNftLootboxLibrary.LootBoxType.MEGA_LOOTBOX_NO_RESERVE,
            "ExilonNftLootboxMain: Only in mega"
        );
        require(isMerging[id] == false, "ExilonNftLootboxMain: Merging");

        uint256 idSupply = totalSupply[id];
        IExilonNftLootboxMaster _masterContract = masterContract;
        require(
            idSupply > 0 && balanceOf(address(_masterContract), id) == idSupply,
            "ExilonNftLootboxMain: Can't merge this id"
        );

        require(
            _masterContract.idsToCreator(id) == msg.sender,
            "ExilonNftLootboxMain: Only creator"
        );

        require(
            nftMarketplace.isTokenModerated(address(this), id),
            "ExilonNftLootboxMain: Only moderated"
        );

        _checkFees(mergePrice);
        _processFeeTransferOnFeeReceiver();

        if (megaType == ExilonNftLootboxLibrary.LootBoxType.MEGA_LOOTBOX_RESERVE) {
            uint256 refundPoolAmount = idSupply * priceHolder.defaultOpeningPrice(megaId);

            require(
                IERC20(usdToken).allowance(msg.sender, address(this)) >= refundPoolAmount,
                "ExilonNftLootboxMain: No enougth allowance for refund"
            );
            IERC20(usdToken).safeTransferFrom(msg.sender, address(this), refundPoolAmount);
            emit RefundFundCollected(msg.sender, refundPoolAmount);

            _mergeRequestInfo.push(
                MergeRequestInfo({
                    id: id,
                    megaId: megaId,
                    requestingAddress: msg.sender,
                    refundPoolAmount: refundPoolAmount
                })
            );

            uint256 prizesLength = _masterContract.getRestPrizesLength(id);
            ExilonNftLootboxLibrary.WinningPlace[] memory prizes = _masterContract
                .getRestPrizesInfo(id, 0, prizesLength);
            (ExilonNftLootboxLibrary.TokenInfo[] memory allTokensInfo, ) = ExilonNftLootboxLibrary
                .processTokensInfo(prizes);
            for (uint256 i = 0; i < allTokensInfo.length; ++i) {
                if (
                    allTokensInfo[i].tokenType == ExilonNftLootboxLibrary.TokenType.ERC20 &&
                    allTokensInfo[i].tokenAddress != usdToken &&
                    allTokensInfo[i].tokenAddress != _weth
                ) {
                    address pair = _pancakeFactory.getPair(allTokensInfo[i].tokenAddress, _weth);
                    require(pair != address(0), "ExilonNftLootboxMain: No token pair with wbnb");
                    (uint256 reserve1, uint256 reserve2, ) = IPancakePair(pair).getReserves();
                    require(
                        reserve1 > 0 && reserve2 > 0,
                        "ExilonNftLootboxMain: Not initialized pair"
                    );
                }
            }
        } else {
            _mergeRequestInfo.push(
                MergeRequestInfo({
                    id: id,
                    megaId: megaId,
                    requestingAddress: msg.sender,
                    refundPoolAmount: 0
                })
            );
        }

        _idToMergeRequestIndex[id] = _mergeRequestInfo.length - 1;
        isMerging[id] = true;
        ++_isMergingToCount[megaId];

        emit MergeRequest(msg.sender, id, megaId);
    }

    function cancelMergeRequest(uint256 id) external nonReentrant {
        MergeRequestInfo memory mergeRequestInfo = _processMergeInput(id);

        require(
            msg.sender == mergeRequestInfo.requestingAddress ||
                msg.sender == address(nftMarketplace),
            "ExilonNftLootboxMain: Only requester"
        );

        if (
            --_isMergingToCount[mergeRequestInfo.megaId] == 0 &&
            totalSupply[mergeRequestInfo.megaId] == 0
        ) {
            _deleteId(mergeRequestInfo.megaId);
        }

        if (mergeRequestInfo.refundPoolAmount > 0) {
            IERC20(usdToken).safeTransfer(
                mergeRequestInfo.requestingAddress,
                mergeRequestInfo.refundPoolAmount
            );
        }

        emit MergeCancel(
            mergeRequestInfo.requestingAddress,
            mergeRequestInfo.id,
            mergeRequestInfo.megaId
        );
    }

    function processMergeRequest(uint256 id, bool decision)
        external
        nonReentrant
        onlyManagerOrAdmin
    {
        MergeRequestInfo memory mergeRequestInfo = _processMergeInput(id);

        if (decision) {
            masterContract.processMerge(mergeRequestInfo.id, mergeRequestInfo.megaId);

            emit MergeSuccess(
                msg.sender,
                mergeRequestInfo.requestingAddress,
                mergeRequestInfo.id,
                mergeRequestInfo.megaId
            );
        } else {
            if (mergeRequestInfo.refundPoolAmount > 0) {
                IERC20(usdToken).safeTransfer(
                    mergeRequestInfo.requestingAddress,
                    mergeRequestInfo.refundPoolAmount
                );
            }

            emit MergeFail(
                msg.sender,
                mergeRequestInfo.requestingAddress,
                mergeRequestInfo.id,
                mergeRequestInfo.megaId
            );
        }

        if (
            --_isMergingToCount[mergeRequestInfo.megaId] == 0 &&
            totalSupply[mergeRequestInfo.megaId] == 0
        ) {
            _deleteId(mergeRequestInfo.megaId);
        }
    }

    function setIdMega(uint256 id, ExilonNftLootboxLibrary.LootBoxType setType)
        external
        nonReentrant
        onlyManagerOrAdmin
    {
        uint256 _totalSupplyId = totalSupply[id];
        IExilonNftLootboxMaster _masterContract = masterContract;
        require(_totalSupplyId > 0, "ExilonNftLootboxMain: Id doesn't exist");
        require(
            balanceOf(address(_masterContract), id) == _totalSupplyId,
            "ExilonNftLootboxMain: Not all lootboxes on the market"
        );

        require(
            lootboxType[id] == ExilonNftLootboxLibrary.LootBoxType.DEFAULT,
            "ExilonNftLootboxMain: Only default"
        );
        require(
            setType == ExilonNftLootboxLibrary.LootBoxType.MEGA_LOOTBOX_RESERVE ||
                setType == ExilonNftLootboxLibrary.LootBoxType.MEGA_LOOTBOX_NO_RESERVE,
            "ExilonNftLootboxMain: Wrong set type"
        );

        _lootBoxTypeToIds[ExilonNftLootboxLibrary.LootBoxType.DEFAULT].remove(id);
        _lootBoxTypeToIds[setType].add(id);

        lootboxType[id] = setType;

        address creator = _masterContract.setWinningPlacesToTheCreator(id);

        if (setType == ExilonNftLootboxLibrary.LootBoxType.MEGA_LOOTBOX_RESERVE) {
            uint256 refundPoolAmount = _totalSupplyId * priceHolder.defaultOpeningPrice(id);

            require(
                IERC20(usdToken).allowance(msg.sender, address(this)) >= refundPoolAmount,
                "ExilonNftLootboxMain: No enougth allowance for refund"
            );
            IERC20(usdToken).safeTransferFrom(msg.sender, address(this), refundPoolAmount);
            emit RefundFundCollected(msg.sender, refundPoolAmount);
        }

        emit MegaLootbox(msg.sender, creator, id, setType);
    }

    function setMergePrice(uint256 newValue) external onlyAdmin {
        mergePrice = newValue;

        emit MergePriceChange(newValue);
    }

    function refundToUser(
        address user,
        address creator,
        uint256 receiveUsdAmount,
        uint256 price
    ) external override onlyMaster {
        uint256 balance = IERC20(usdToken).balanceOf(address(this));

        uint256 refundUsdAmount;
        if (price > receiveUsdAmount) {
            refundUsdAmount = price - receiveUsdAmount;
        }

        if (refundUsdAmount > balance) {
            refundUsdAmount = balance;
        }
        if (refundUsdAmount > 0) {
            IERC20(usdToken).safeTransfer(user, refundUsdAmount);
            balance -= refundUsdAmount;
        }

        uint256 refundToCreator = price - refundUsdAmount;
        if (refundToCreator > balance) {
            refundToCreator = balance;
        }
        if (refundToCreator > 0) {
            IERC20(usdToken).safeTransfer(creator, refundToCreator);
        }

        emit RefundPaid(user, creator, refundUsdAmount, refundToCreator);
    }

    function mint(
        address to,
        uint256 id,
        uint256 amount,
        string memory _uri
    ) external override onlyMaster {
        _mint(to, id, amount, "");

        uint256 __totalSupply = totalSupply[id];
        if (__totalSupply == 0 && _isMergingToCount[id] == 0) {
            _lootBoxTypeToIds[ExilonNftLootboxLibrary.LootBoxType.DEFAULT].add(id);

            _idsToUri[id] = _uri;
            emit URI(_uri, id);
        }
        __totalSupply += amount;
        totalSupply[id] = __totalSupply;
    }

    function burn(
        address from,
        uint256 id,
        uint256 amount
    ) external override onlyMaster {
        _burn(from, id, amount);

        uint256 __totalSupply = totalSupply[id];
        __totalSupply -= amount;
        totalSupply[id] = __totalSupply;

        if (__totalSupply == 0 && _isMergingToCount[id] == 0) {
            _deleteId(id);
        }
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

        if (indexFrom >= indexTo || indexTo > len) {
            return result;
        }

        result = new uint256[](indexTo - indexFrom);
        for (uint256 i = indexFrom; i < indexTo; ++i) {
            result[i - indexFrom] = _idsUsersHold[user].at(i);
        }
    }

    function mergeRequestsLen() external view returns (uint256) {
        return _mergeRequestInfo.length;
    }

    function mergeRequestsIndex(uint256 indexFrom, uint256 indexTo)
        external
        view
        returns (MergeRequestInfo[] memory result)
    {
        uint256 fullLength = _mergeRequestInfo.length;
        if (indexFrom >= indexTo || indexTo > fullLength) {
            return result;
        }

        result = new MergeRequestInfo[](indexTo - indexFrom);
        for (uint256 i = indexFrom; i < indexTo; ++i) {
            result[i - indexFrom] = _mergeRequestInfo[i];
        }
    }

    function getLootboxTypeLength(ExilonNftLootboxLibrary.LootBoxType _type)
        external
        view
        returns (uint256)
    {
        return _lootBoxTypeToIds[_type].length();
    }

    function getLootboxTypeIds(
        ExilonNftLootboxLibrary.LootBoxType _type,
        uint256 indexFrom,
        uint256 indexTo
    ) external view returns (uint256[] memory result) {
        uint256 fullLength = _lootBoxTypeToIds[_type].length();
        if (indexFrom >= indexTo || indexTo > fullLength) {
            return result;
        }

        result = new uint256[](indexTo - indexFrom);
        for (uint256 i = indexFrom; i < indexTo; ++i) {
            result[i - indexFrom] = _lootBoxTypeToIds[_type].at(i);
        }
    }

    function getBnbPriceToMergeRequest() external view returns (uint256) {
        return _getBnbAmountToFront(mergePrice);
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

    function _processMergeInput(uint256 id)
        private
        returns (MergeRequestInfo memory mergeRequestInfo)
    {
        require(isMerging[id], "ExilonNftLootboxMain: Not merging");
        delete isMerging[id];

        uint256 requestIndex = _idToMergeRequestIndex[id];
        delete _idToMergeRequestIndex[id];

        mergeRequestInfo = _mergeRequestInfo[requestIndex];

        uint256 requestsLength = _mergeRequestInfo.length;
        if (requestIndex < requestsLength - 1) {
            MergeRequestInfo memory replacement = _mergeRequestInfo[requestsLength - 1];
            _mergeRequestInfo[requestIndex] = replacement;

            _idToMergeRequestIndex[replacement.id] = requestIndex;
        }
        _mergeRequestInfo.pop();
    }

    function _deleteId(uint256 id) private {
        delete _idsToUri[id];
        emit URI("", id);

        ExilonNftLootboxLibrary.LootBoxType _type = lootboxType[id];
        delete lootboxType[id];
        _lootBoxTypeToIds[_type].remove(id);

        masterContract.deleteId(id);
    }

    function uri(uint256 id) public view virtual override returns (string memory) {
        return _idsToUri[id];
    }

    function getUrisOfBatch(uint256[] memory ids) external view returns (string[] memory result) {
        if (ids.length == 0) {
            return result;
        }
        result = new string[](ids.length);
        for (uint256 i = 0; i < ids.length; ++i) {
            result[i] = _idsToUri[ids[i]];
        }
    }

    function balanceOfBatchIds(address user, uint256[] memory ids)
        external
        view
        returns (uint256[] memory result)
    {
        if (ids.length == 0) {
            return result;
        }
        result = new uint256[](ids.length);
        for (uint256 i = 0; i < ids.length; ++i) {
            result[i] = balanceOf(user, ids[i]);
        }
    }
}
