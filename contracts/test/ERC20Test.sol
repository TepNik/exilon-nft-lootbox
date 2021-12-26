// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.11;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract ERC20Test is ERC20 {
    bool isTransfersDisabled;

    constructor() ERC20("Test Token", "TEST") {}

    function mint(uint256 amount) external {
        _mint(msg.sender, amount);
    }

    function switchTransfers() external {
        isTransfersDisabled = !isTransfersDisabled;
    }

    function _beforeTokenTransfer(
        address ,
        address ,
        uint256
    ) internal virtual override {
        require(!isTransfersDisabled, "ERC20Test: Transfers disabled");
    }
}
