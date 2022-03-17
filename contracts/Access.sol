// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.12;

import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";

import "./interfaces/IAccess.sol";

contract Access is AccessControlEnumerable, IAccess {
    bytes32 public constant override MANAGER_ROLE = keccak256("MANAGER_ROLE");

    constructor() {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }
}
