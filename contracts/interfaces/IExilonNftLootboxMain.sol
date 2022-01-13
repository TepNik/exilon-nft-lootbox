// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.11;

import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

import "../ExilonNftLootboxLibrary.sol";

interface IExilonNftLootboxMain is IERC1155 {
    function init() external;

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
}
