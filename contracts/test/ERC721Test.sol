// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract ERC721Test is ERC721 {
    mapping(uint256 => string) tokensUri;

    constructor() ERC721("ERC721 Test 3", "ERC721") {}

    function setTokenUri(uint256 id, string calldata uri) external {
        tokensUri[id] = uri;
    }

    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        return tokensUri[tokenId];
    }

    function mint(uint256 tokenId) external {
        _safeMint(msg.sender, tokenId);
    }
}
