// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.11;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";

contract ERC1155Test is ERC1155 {
    bool isTransfersDisabled;

    constructor() ERC1155("https://site.com/{id}.json") {}

    function mint(uint256 tokenId, uint256 amount) external {
        _mint(msg.sender, tokenId, amount, "");
    }

    function setUri(string calldata newUri) external {
        _setURI(newUri);
    }

    function switchTransfers() external {
        isTransfersDisabled = !isTransfersDisabled;
    }

    function _beforeTokenTransfer(
        address,
        address,
        address,
        uint256[] memory,
        uint256[] memory,
        bytes memory
    ) internal virtual override {
        require(!isTransfersDisabled, "ERC1155Test: Transfers disabled");
    }
}
