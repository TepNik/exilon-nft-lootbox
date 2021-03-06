// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.12;

interface IPancakeCallee {
    function pancakeCall(
        address sender,
        uint256 amount0,
        uint256 amount1,
        bytes calldata data
    ) external;
}
