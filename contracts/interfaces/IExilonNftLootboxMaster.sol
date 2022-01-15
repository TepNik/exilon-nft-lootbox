// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.11;

import "../ExilonNftLootboxLibrary.sol";

interface IExilonNftLootboxMaster {
    function idsToCreator(uint256 id) external view returns (address);

    function processMerge(uint256 idFrom, uint256 idTo) external;

    function defaultOpeningPrice(uint256 id) external view returns (uint256);

    function setWinningPlacesToTheCreator(uint256 id) external;

    function getRestPrizesLength(uint256 id) external view returns (uint256);

    function getRestPrizesInfo(
        uint256 id,
        uint256 indexFrom,
        uint256 indexTo
    ) external view returns (ExilonNftLootboxLibrary.WinningPlace[] memory result);
}
