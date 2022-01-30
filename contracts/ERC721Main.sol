// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.11;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import "./pancake-swap/interfaces/IPancakeRouter02.sol";

import "./FeeCalculator.sol";
import "./FeeSender.sol";

contract ERC721Main is FeeCalculator, FeeSender, ERC721 {
    // public

    uint256 public creatingPrice;

    // private

    uint256 private _lastId;
    mapping(uint256 => string) private _idsToUri;

    event MadedNft(address indexed user, uint256 id, string uri);

    event CreatingPriceChange(uint256 newValue);

    constructor(
        address _usdToken,
        IPancakeRouter02 _pancakeRouter,
        address _feeReceiver,
        IAccess _accessControl
    )
        ERC721("Exilon NFT ERC721", "EXL721")
        FeeCalculator(_usdToken, _pancakeRouter)
        FeeSender(_feeReceiver)
        AccessConnector(_accessControl)
    {
        creatingPrice = _oneUsd;

        emit CreatingPriceChange(_oneUsd);
    }

    function makeNft(string memory _uri) external payable nonReentrant onlyEOA {
        _checkFees(creatingPrice);
        _processFeeTransferOnFeeReceiver();

        uint256 __lastId = _lastId++;

        _idsToUri[__lastId] = _uri;

        _mint(msg.sender, __lastId);

        emit MadedNft(msg.sender, __lastId, _uri);
    }

    function setCreatingPrice(uint256 newValue) external onlyAdmin {
        creatingPrice = newValue;

        emit CreatingPriceChange(newValue);
    }

    function getBnbPriceToCreate() external view returns (uint256) {
        return _getBnbAmountToFront(creatingPrice);
    }

    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        return _idsToUri[tokenId];
    }
}
