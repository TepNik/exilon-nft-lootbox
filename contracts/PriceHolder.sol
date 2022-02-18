// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.11;

import "./pancake-swap/interfaces/IPancakeRouter02.sol";

import "./FeeCalculator.sol";

import "./interfaces/IAccess.sol";
import "./interfaces/IExilonNftLootboxMain.sol";
import "./interfaces/IExilonNftLootboxMaster.sol";
import "./interfaces/IPriceHolder.sol";

contract PriceHolder is FeeCalculator, IPriceHolder {
    IExilonNftLootboxMain public immutable exilonNftLootboxMain;
    IExilonNftLootboxMaster public exilonNftLootboxMaster;

    // Amount in USD for creating lootbox
    uint256 public override creatingPrice;
    // Minimal amount in USD for openning price
    uint256 public override minimumOpeningPrice;
    // Connects id with it's openning price
    mapping(uint256 => uint256) public override defaultOpeningPrice;
    // Percentage from openning price that the creators will get (100% - 10_000)
    uint256 public override creatorPercentage = 9_000; // 90%

    // Parameters for random
    uint256 public minRandomPercentage = 9_000; // 90%
    uint256 public maxRandomPercentage = 15_000; // 150%
    uint256 public powParameter = 5;

    // Airdrop token
    IERC20 public airdropToken;
    // Amount of exilon tokens that the openers of lootboxes will get
    uint256 public amountOfAirdropTokenToOpenner;

    // Parameters for opening price of mega lootboxes
    uint256 public maxOpeningPricePercentage = 20_000; // 200%
    uint256 public priceDeltaPercentage = 100; // 1%
    uint256 public priceTimeDelta = 5 minutes;

    struct LootboxPurchaseInfo {
        uint256 price;
        uint256 timestamp;
    }
    // Connects
    mapping(uint256 => mapping(address => LootboxPurchaseInfo)) private _lastPurchase;

    modifier onlyMaster() {
        require(msg.sender == address(exilonNftLootboxMaster), "PriceHolder: Only master");
        _;
    }

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
    event ChangeAirdropParams(address airdropToken, uint256 airdropAmount);
    event OpeningPriceForIdChanged(uint256 id, uint256 newOpeningPrice);
    event OpeningPriceForMegaLootboxesChange(
        uint256 newMaxOpeningPricePercentage,
        uint256 newPriceDeltaPercentage,
        uint256 newPriceTimeDelta
    );

    event GoodAirdropTransfer(address indexed token, address indexed to, uint256 amount);
    event BadAirdropTransfer(
        address indexed token,
        address indexed to,
        uint256 amount,
        string transferError
    );

    constructor(
        IERC20 _airdropToken,
        address _usdToken,
        IPancakeRouter02 _pancakeRouter,
        IAccess _accessControl,
        IExilonNftLootboxMain _exilonNftLootboxMain
    ) FeeCalculator(_usdToken, _pancakeRouter) AccessConnector(_accessControl) {
        exilonNftLootboxMain = _exilonNftLootboxMain;

        creatingPrice = _oneUsd;
        minimumOpeningPrice = _oneUsd;

        if (address(_airdropToken) != address(0)) {
            uint256 oneAirdropToken = 10**IERC20Metadata(address(_airdropToken)).decimals();
            amountOfAirdropTokenToOpenner = oneAirdropToken;
            airdropToken = _airdropToken;

            emit ChangeAirdropParams(address(_airdropToken), oneAirdropToken);
        }

        emit RandomParamsChange(minRandomPercentage, maxRandomPercentage, powParameter);
    }

    function init() external override {
        require(address(exilonNftLootboxMaster) == address(0), "PriceHolder: Only once");

        exilonNftLootboxMaster = IExilonNftLootboxMaster(msg.sender);
    }

    function setDefaultOpeningPrice(uint256 id, uint256 openingPrice) external override onlyMaster {
        require(openingPrice >= minimumOpeningPrice, "PriceHolder: Opening price is too low");

        defaultOpeningPrice[id] = openingPrice;
    }

    function withdrawToken(IERC20 token, uint256 amount) external onlyAdmin nonReentrant {
        ExilonNftLootboxLibrary.sendTokenCarefully(token, msg.sender, amount, true);
    }

    function airdropToOpenner(address user) external override onlyMaster {
        IERC20 _airdropToken = airdropToken;
        (bool success, uint256 amount, string memory transferError) = ExilonNftLootboxLibrary
            .sendTokenCarefully(_airdropToken, user, amountOfAirdropTokenToOpenner, false);

        if (!success) {
            emit BadAirdropTransfer(address(_airdropToken), msg.sender, amount, transferError);
        } else {
            emit GoodAirdropTransfer(address(_airdropToken), msg.sender, amount);
        }
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

    function setPriceInfo(
        uint256 _creatingPrice,
        uint256 _minimumOpeningPrice,
        uint256 _creatorPercentage
    ) external onlyAdmin {
        require(
            _creatorPercentage >= 5_000 && _creatorPercentage <= 10_000,
            "ExilonNftLootboxMaster: Percentage"
        );
        require(_minimumOpeningPrice > 0, "ExilonNftLootboxMaster: Min price");
        require(_creatingPrice > 0, "ExilonNftLootboxMaster: Creating price");

        creatingPrice = _creatingPrice;
        minimumOpeningPrice = _minimumOpeningPrice;
        creatorPercentage = _creatorPercentage;

        emit PriceChanges(_creatingPrice, _minimumOpeningPrice, _creatorPercentage);
    }

    function setOpeningPriceForMegaLootboxes(
        uint256 newMaxOpeningPricePercentage,
        uint256 newPriceDeltaPercentage,
        uint256 newPriceTimeDelta
    ) external onlyAdmin {
        require(
            newMaxOpeningPricePercentage >= 10_000 && newMaxOpeningPricePercentage <= 100_000,
            "ExilonNftLootboxMaster: Max"
        );
        require(newPriceDeltaPercentage <= 1_000, "ExilonNftLootboxMaster: Price delta");
        require(newPriceTimeDelta <= 1 days, "ExilonNftLootboxMaster: Time delta");

        maxOpeningPricePercentage = newMaxOpeningPricePercentage;
        priceDeltaPercentage = newPriceDeltaPercentage;
        priceTimeDelta = newPriceTimeDelta;

        emit OpeningPriceForMegaLootboxesChange(
            newMaxOpeningPricePercentage,
            newPriceDeltaPercentage,
            newPriceTimeDelta
        );
    }

    function setOpeningPriceForId(uint256 id, uint256 newOpeningPrice) external {
        require(newOpeningPrice >= minimumOpeningPrice, "PriceHolder: Opening price is too low");
        require(
            msg.sender == exilonNftLootboxMaster.idsToCreator(id) ||
                accessControl.hasRole(bytes32(0), msg.sender),
            "ExilonNftLootboxMaster: No access"
        );
        require(exilonNftLootboxMain.totalSupply(id) > 0, "ExilonNftLootboxMaster: No such id");
        require(
            exilonNftLootboxMain.lootboxType(id) !=
                ExilonNftLootboxLibrary.LootBoxType.MEGA_LOOTBOX_RESERVE,
            "ExilonNftLootboxMaster: No refund box"
        );

        defaultOpeningPrice[id] = newOpeningPrice;

        emit OpeningPriceForIdChanged(id, newOpeningPrice);
    }

    function makePurchase(
        address user,
        uint256 id,
        ExilonNftLootboxLibrary.LootBoxType boxType,
        address boxCreator,
        uint256 amount
    ) external override onlyMaster returns (uint256 newPrice) {
        newPrice = _calculatePrice(user, id, boxType, boxCreator, amount);
        if (boxType != ExilonNftLootboxLibrary.LootBoxType.DEFAULT) {
            _lastPurchase[id][user].price = newPrice / amount;
            _lastPurchase[id][user].timestamp = block.timestamp;
        }
    }

    function getRandomParameters()
        external
        view
        returns (
            uint256 _minRandomPercentage,
            uint256 _maxRandomPercentage,
            uint256 _powParameter
        )
    {
        return (minRandomPercentage, maxRandomPercentage, powParameter);
    }

    function getOpeningPrice(
        address user,
        uint256 id,
        uint256 amount
    ) public view override returns (uint256) {
        return
            _calculatePrice(
                user,
                id,
                exilonNftLootboxMain.lootboxType(id),
                exilonNftLootboxMaster.idsToCreator(id),
                amount
            );
    }

    function _calculatePrice(
        address user,
        uint256 id,
        ExilonNftLootboxLibrary.LootBoxType boxType,
        address boxCreator,
        uint256 amount
    ) private view returns (uint256) {
        uint256 minPrice = defaultOpeningPrice[id];
        if (boxType != ExilonNftLootboxLibrary.LootBoxType.DEFAULT) {
            LootboxPurchaseInfo memory lastPurchase = _lastPurchase[id][user];

            if (
                lastPurchase.timestamp == 0 ||
                lastPurchase.price == 0 ||
                lastPurchase.timestamp + priceTimeDelta < block.timestamp
            ) {
                lastPurchase.price = minPrice;
            }
            uint256 maxPrice = (minPrice * maxOpeningPricePercentage) / 10_000;
            uint256 priceNow = lastPurchase.price +
                (minPrice * priceDeltaPercentage * amount) /
                10_000;
            if (priceNow > maxPrice) {
                priceNow = maxPrice;
            }
            return priceNow * amount;
        } else {
            if (user == boxCreator) {
                return 0;
            } else {
                return minPrice * amount;
            }
        }
    }

    function getBnbPriceToCreate() external view returns (uint256) {
        return _getBnbAmountToFront(creatingPrice);
    }

    function getBnbPriceToOpen(
        address user,
        uint256 id,
        uint256 amount
    ) external view returns (uint256) {
        return _getBnbAmountToFront(getOpeningPrice(user, id, amount));
    }

    function getBnbPriceToOpenBatchIds(
        address user,
        uint256 amount,
        uint256[] memory ids
    ) external view returns (uint256[] memory result) {
        if (ids.length == 0) {
            return result;
        }

        result = new uint256[](ids.length);
        for (uint256 i = 0; i < ids.length; ++i) {
            result[i] = _getBnbAmountToFront(getOpeningPrice(user, ids[i], amount));
        }
    }
}
