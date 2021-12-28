// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.11;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import "./pancake-swap/interfaces/IPancakeRouter02.sol";

import "./FeesCalculator.sol";

contract ERC721Main is FeesCalculator, ERC721, ReentrancyGuard {
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
        address _feeReceiver
    )
        ERC721("Exilon NFT ERC721", "EXL721")
        FeesCalculator(_usdToken, _pancakeRouter, _feeReceiver)
    {
        uint256 oneDollar = 10**IERC20Metadata(_usdToken).decimals();
        creatingPrice = oneDollar;

        emit CreatingPriceChange(oneDollar);
    }

    function makeNft(string memory _uri) external payable nonReentrant onlyEOA {
        _checkFees(creatingPrice);
        _processFeeTransferOnFeeReceiver();

        uint256 __lastId = _lastId;
        _lastId = __lastId + 1;

        _idsToUri[__lastId] = _uri;

        _mint(msg.sender, __lastId);

        emit MadedNft(msg.sender, __lastId, _uri);
    }

    function getBnbPriceToCreate() external view returns (uint256) {
        return _getBnbAmountToFront(creatingPrice);
    }

    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        return _idsToUri[tokenId];
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(AccessControl, ERC721)
        returns (bool)
    {
        return
            AccessControl.supportsInterface(interfaceId) || ERC721.supportsInterface(interfaceId);
    }
}