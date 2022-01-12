// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.11;

import "../ExilonNftLootboxLibrary.sol";

interface IFundsHolder {
    function init(address _master) external;

    function withdrawTokens(ExilonNftLootboxLibrary.TokenInfo[] memory tokenInfo, address to) external;

    function withdrawToken(ExilonNftLootboxLibrary.TokenInfo memory tokenInfo, address to)
        external returns (bool);

    function selfDestruct() external;
}