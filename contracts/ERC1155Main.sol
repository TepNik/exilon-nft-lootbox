// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.11;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import "./pancake-swap/interfaces/IPancakeRouter02.sol";

import "./FeeCalculator.sol";
import "./FeeSender.sol";

contract ERC1155Main is FeeCalculator, FeeSender, ERC1155 {
    // public

    uint256 public creatingPrice;

    // private

    uint256 private _lastId;
    mapping(uint256 => string) private _idsToUri;

    event MadedNft(address indexed user, uint256 id, uint256 amount, string uri);

    event CreatingPriceChange(uint256 newValue);

    constructor(
        address _usdToken,
        IPancakeRouter02 _pancakeRouter,
        address _feeReceiver,
        IAccess _accessControl
    )
        ERC1155("")
        FeeCalculator(_usdToken, _pancakeRouter)
        FeeSender(_feeReceiver)
        AccessConnector(_accessControl)
    {
        creatingPrice = _oneUsd;

        emit CreatingPriceChange(_oneUsd);
    }

    function makeNft(uint256 amount, string memory _uri) external payable nonReentrant onlyEOA {
        _checkFees(creatingPrice);
        _processFeeTransferOnFeeReceiver();

        uint256 __lastId = _lastId;
        _lastId = __lastId + 1;

        _mint(msg.sender, __lastId, amount, "");

        _idsToUri[__lastId] = _uri;
        emit URI(_uri, __lastId);

        emit MadedNft(msg.sender, __lastId, amount, _uri);
    }

    function setCreatingPrice(uint256 newValue) external onlyAdmin {
        creatingPrice = newValue;

        emit CreatingPriceChange(newValue);
    }

    function getBnbPriceToCreate() external view returns (uint256) {
        return _getBnbAmountToFront(creatingPrice);
    }

    function uri(uint256 id) public view virtual override returns (string memory) {
        return _idsToUri[id];
    }
}
