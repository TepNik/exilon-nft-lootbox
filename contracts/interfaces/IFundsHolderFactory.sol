// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.12;

interface IFundsHolderFactory {
    function init() external;

    function deployNewContract() external returns (address);
}
