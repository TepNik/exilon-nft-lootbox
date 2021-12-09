// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";

contract ERC1155Test is ERC1155 {
    constructor() ERC1155("https://site.com/{id}.json") {}

    function mint(uint256 tokenId, uint256 amount) external {
        _mint(msg.sender, tokenId, amount, "");
    }

    function setUri(string calldata newUri) external {
        _setURI(newUri);
    }
}
