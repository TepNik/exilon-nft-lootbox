// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.11;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "./pancake-swap/interfaces/IPancakeRouter02.sol";

import "./FeesCalculator.sol";

import "./interfaces/IExilonNftLootboxMain.sol";

contract ExilonNftLootboxMain is ERC1155, FeesCalculator, IExilonNftLootboxMain {
    using EnumerableSet for EnumerableSet.UintSet;

    // public

    address public masterContract;

    // private

    mapping(address => EnumerableSet.UintSet) private _idsUsersHold;
    mapping(uint256 => string) private _idsToUri;

    modifier onlyMaster() {
        require(msg.sender == masterContract, "ExilonNftLootboxMain: Not master");
        _;
    }

    constructor(
        address _usdToken,
        IPancakeRouter02 _pancakeRouter,
        address _feeReceiver
    ) ERC1155("") FeesCalculator(_usdToken, _pancakeRouter, _feeReceiver) {}

    function init() external override {
        masterContract = msg.sender;
    }

    function mint(
        address to,
        uint256 id,
        uint256 amount,
        string memory _uri
    ) external onlyMaster {
        _mint(to, id, amount, "");

        _idsToUri[id] = _uri;
        emit URI(_uri, id);
    }

    function burn(
        address from,
        uint256 id,
        uint256 amount
    ) external override onlyMaster {
        _burn(from, id, amount);
    }

    function deleteId(uint256 id) external override onlyMaster {
        delete _idsToUri[id];
        emit URI("", id);
    }

    function getUsersIdsLength(address user) external view returns (uint256) {
        return _idsUsersHold[user].length();
    }

    function getUsersIds(
        address user,
        uint256 indexFrom,
        uint256 indexTo
    ) external view returns (uint256[] memory result) {
        uint256 len = _idsUsersHold[user].length();

        if (indexFrom >= indexTo || indexFrom > len || indexTo > len) {
            return new uint256[](0);
        }

        result = new uint256[](indexTo - indexFrom);
        for (uint256 i = indexFrom; i < indexTo; ++i) {
            result[i] = _idsUsersHold[user].at(i);
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
                    _idsUsersHold[from].remove(ids[i]);
                }
            }
            if (to != address(0) && amounts[i] > 0) {
                _idsUsersHold[to].add(ids[i]);
            }
        }
    }

    function uri(uint256 id) public view virtual override returns (string memory) {
        return _idsToUri[id];
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(AccessControl, ERC1155, IERC165)
        returns (bool)
    {
        return
            AccessControl.supportsInterface(interfaceId) || ERC1155.supportsInterface(interfaceId);
    }
}
