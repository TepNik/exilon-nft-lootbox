// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.11;

import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";

import "./ExilonNftLootboxLibrary.sol";

contract FundsHolder is ERC1155Holder, ERC721Holder {
    bool isInited;

    address public factory;

    modifier onlyFactory() {
        require(msg.sender == factory, "FundsHolder: Not allowed");
        _;
    }

    constructor() {}

    function init() external {
        require(!isInited, "FundsHolder: Already initied");
        isInited = true;

        factory = msg.sender;
    }

    function withdrawTokens(ExilonNftLootboxLibrary.TokenInfo[] memory tokenInfo, address to)
        external
        onlyFactory
    {
        for (uint256 i = 0; i < tokenInfo.length; ++i) {
            ExilonNftLootboxLibrary.withdrawToken(tokenInfo[i], address(this), to, false);
        }
    }

    function withdrawToken(ExilonNftLootboxLibrary.TokenInfo memory tokenInfo, address to)
        external
        onlyFactory
    {
        ExilonNftLootboxLibrary.withdrawToken(tokenInfo, address(this), to, false);
    }

    function selfDestruct() external onlyFactory {
        selfdestruct(payable(msg.sender));
    }
}
