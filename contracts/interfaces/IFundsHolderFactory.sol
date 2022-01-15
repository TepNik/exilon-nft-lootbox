// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.11;

interface IFundsHolderFactory {
    function init() external;

    function deployNewContract() external returns (address);
}
