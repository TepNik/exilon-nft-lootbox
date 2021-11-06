// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract ExilonNftLootbox is ERC1155, IERC1155Receiver, IERC721Receiver {
    using EnumerableSet for EnumerableSet.UintSet;

    mapping(address => EnumerableSet.UintSet) private idsUsersHold;

    constructor(string memory _uri) ERC1155(_uri) {}

    function getUsersIds(address user) external view returns (uint256[] memory result) {
        uint256 len = idsUsersHold[user].length();
        result = new uint256[](len);
        for (uint256 i = 0; i < len; ++i) {
            result[i] = idsUsersHold[user].at(i);
        }
    }

    function _beforeTokenTransfer(
        address,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory
    ) internal virtual override {
        for (uint256 i = 0; i < ids.length; ++i) {
            if (from != address(0)) {
                uint256 balanceFrom = balanceOf(from, ids[i]);
                if (amounts[i] > 0 && balanceFrom <= amounts[i]) {
                    idsUsersHold[from].remove(ids[i]);
                }
            }
            if (to != address(0) && amounts[i] > 0) {
                idsUsersHold[to].add(ids[i]);
            }
        }
    }

    function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes calldata
    ) external pure returns (bytes4) {
        return IERC1155Receiver.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address,
        address,
        uint256[] calldata,
        uint256[] calldata,
        bytes calldata
    ) external pure returns (bytes4) {
        return IERC1155Receiver.onERC1155BatchReceived.selector;
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }
}
