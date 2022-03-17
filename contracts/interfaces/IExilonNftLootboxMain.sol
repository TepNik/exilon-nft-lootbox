// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.12;

import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

import "../ExilonNftLootboxLibrary.sol";

interface IExilonNftLootboxMain is IERC1155 {
    function init(address _priceHolder) external;

    function isMerging(uint256 id) external view returns (bool);

    function totalSupply(uint256 id) external view returns (uint256);

    function cancelMergeRequest(uint256 id) external;

    function mint(
        address to,
        uint256 id,
        uint256 amount,
        string memory uri
    ) external;

    function burn(
        address from,
        uint256 id,
        uint256 amount
    ) external;

    function lootboxType(uint256 id) external view returns (ExilonNftLootboxLibrary.LootBoxType);

    function refundToUser(
        address user,
        address creator,
        uint256 receiveUsdAmount,
        uint256 price
    ) external;
}
