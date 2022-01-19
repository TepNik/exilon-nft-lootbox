// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.11;

import "../ExilonNftLootboxLibrary.sol";

interface IPriceHolder {
    function init() external;

    function creatorPercentage() external view returns (uint256);

    function creatingPrice() external view returns (uint256);

    function minimumOpeningPrice() external view returns (uint256);

    function defaultOpeningPrice(uint256 id) external view returns (uint256);

    function setDefaultOpeningPrice(uint256 id, uint256 openingPrice) external;

    function makePurchase(
        address user,
        uint256 id,
        ExilonNftLootboxLibrary.LootBoxType boxType,
        uint256 amount
    ) external returns (uint256);

    function getOpeningPrice(
        address user,
        uint256 id,
        uint256 amount
    ) external view returns (uint256);
}
