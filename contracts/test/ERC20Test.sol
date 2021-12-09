// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract ERC20Test is ERC20 {
    constructor() ERC20("Test Token 3", "TEST1") {
        _mint(msg.sender, 10**18);
    }

    function mint(uint256 amount) external {
        _mint(msg.sender, amount);
    }
}
