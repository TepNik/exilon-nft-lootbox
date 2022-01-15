// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.11;

import "@openzeppelin/contracts/access/IAccessControl.sol";

interface IAccess is IAccessControl {
    function MANAGER_ROLE() external view returns (bytes32);
}
