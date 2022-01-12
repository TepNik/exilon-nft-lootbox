// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.11;

import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";

import "./ExilonNftLootboxLibrary.sol";

import "./interfaces/IFundsHolder.sol";

contract FundsHolder is ERC1155Holder, ERC721Holder, IFundsHolder {
    bool isInited;

    address public master;

    modifier onlyMaster() {
        require(msg.sender == master, "FundsHolder: Not allowed");
        _;
    }

    constructor() {}

    function init(address _master) external override {
        require(!isInited, "FundsHolder: Already initied");
        isInited = true;

        master = _master;
    }

    function withdrawTokens(ExilonNftLootboxLibrary.TokenInfo[] memory tokenInfo, address to)
        external
        override
        onlyMaster
    {
        for (uint256 i = 0; i < tokenInfo.length; ++i) {
            ExilonNftLootboxLibrary.withdrawToken(tokenInfo[i], address(this), to, false);
        }
    }

    function withdrawToken(ExilonNftLootboxLibrary.TokenInfo memory tokenInfo, address to)
        external
        override
        onlyMaster
        returns (bool)
    {
        return ExilonNftLootboxLibrary.withdrawToken(tokenInfo, address(this), to, false);
    }

    function selfDestruct() external override onlyMaster {
        selfdestruct(payable(msg.sender));
    }
}
