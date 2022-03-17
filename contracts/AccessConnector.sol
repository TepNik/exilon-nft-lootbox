// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.12;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "./interfaces/IAccess.sol";

contract AccessConnector is ReentrancyGuard {
    IAccess public immutable accessControl;

    bytes32 private immutable _MANAGER_ROLE;

    modifier onlyAdmin() {
        require(accessControl.hasRole(bytes32(0), msg.sender), "ExilonNftLootbox: No access");
        _;
    }

    modifier onlyManagerOrAdmin() {
        require(
            accessControl.hasRole(_MANAGER_ROLE, msg.sender) ||
                accessControl.hasRole(bytes32(0), msg.sender),
            "ExilonNftLootbox: No access"
        );
        _;
    }

    constructor(IAccess _accessControl) {
        accessControl = _accessControl;
        _MANAGER_ROLE = _accessControl.MANAGER_ROLE();
    }
}
