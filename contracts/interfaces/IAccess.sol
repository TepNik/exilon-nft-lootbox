// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.12;

import "@openzeppelin/contracts/access/IAccessControl.sol";

interface IAccess is IAccessControl {
    function MANAGER_ROLE() external view returns (bytes32);
}
