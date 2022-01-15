// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.11;

interface INftMarketplace {
    function isTokenModerated(address token, uint256 id) external view returns (bool);
}
