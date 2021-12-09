// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

library ExilonNftLootboxLibrary {
    using SafeERC20 for IERC20;

    enum TokenType {
        ERC20,
        ERC721,
        ERC1155
    }

    struct TokenInfo {
        address tokenAddress;
        TokenType tokenType;
        uint256 id; // for ERC721 and ERC1155. For ERC20 must be 0
        uint256 amount; // for ERC20 and ERC1155. For ERC721 must be 0
    }

    struct WinningPlace {
        uint256 placeAmounts;
        TokenInfo[] prizesInfo;
    }

    uint256 public constant MAX_TOKENS_IN_LOOTBOX = 200;
    uint256 public constant MAX_GAS_FOR_TRANSFER = 5_000_000;

    event BadERC20TokenWithdraw(
        address indexed token,
        address indexed from,
        address indexed to,
        uint256 amount
    );
    event BadERC721TokenWithdraw(
        address indexed token,
        address indexed from,
        address indexed to,
        uint256 id
    );
    event BadERC1155TokenWithdraw(
        address indexed token,
        address indexed from,
        address indexed to,
        uint256 id,
        uint256 amount
    );

    function withdrawToken(
        TokenInfo memory tokenInfo,
        address from,
        address to,
        bool requireSuccess
    ) external {
        if (tokenInfo.tokenType == TokenType.ERC20) {
            if (from == address(this)) {
                if (requireSuccess) {
                    IERC20(tokenInfo.tokenAddress).safeTransfer(to, tokenInfo.amount);
                } else {
                    (bool success, ) = tokenInfo.tokenAddress.call{ gas: MAX_GAS_FOR_TRANSFER }(
                        abi.encodeWithSelector(IERC20.transfer.selector, to, tokenInfo.amount)
                    );
                    if (!success) {
                        emit BadERC20TokenWithdraw(
                            tokenInfo.tokenAddress,
                            from,
                            to,
                            tokenInfo.amount
                        );
                    }
                }
            } else {
                if (requireSuccess) {
                    IERC20(tokenInfo.tokenAddress).safeTransferFrom(from, to, tokenInfo.amount);
                } else {
                    (bool success, ) = tokenInfo.tokenAddress.call{ gas: MAX_GAS_FOR_TRANSFER }(
                        abi.encodeWithSelector(
                            IERC20.transferFrom.selector,
                            from,
                            to,
                            tokenInfo.amount
                        )
                    );
                    if (!success) {
                        emit BadERC20TokenWithdraw(
                            tokenInfo.tokenAddress,
                            from,
                            to,
                            tokenInfo.amount
                        );
                    }
                }
            }
        } else if (tokenInfo.tokenType == TokenType.ERC721) {
            if (requireSuccess) {
                IERC721(tokenInfo.tokenAddress).safeTransferFrom(from, to, tokenInfo.id);
            } else {
                (bool success, ) = tokenInfo.tokenAddress.call{ gas: MAX_GAS_FOR_TRANSFER }(
                    abi.encodeWithSignature(
                        "safeTransferFrom(address,address,uint256)",
                        from,
                        to,
                        tokenInfo.id
                    )
                );
                if (!success) {
                    emit BadERC721TokenWithdraw(tokenInfo.tokenAddress, from, to, tokenInfo.id);
                }
            }
        } else if (tokenInfo.tokenType == TokenType.ERC1155) {
            if (requireSuccess) {
                IERC1155(tokenInfo.tokenAddress).safeTransferFrom(
                    from,
                    to,
                    tokenInfo.id,
                    tokenInfo.amount,
                    ""
                );
            } else {
                (bool success, ) = tokenInfo.tokenAddress.call{ gas: MAX_GAS_FOR_TRANSFER }(
                    abi.encodeWithSelector(
                        IERC1155.safeTransferFrom.selector,
                        from,
                        to,
                        tokenInfo.id,
                        tokenInfo.amount,
                        ""
                    )
                );
                if (!success) {
                    emit BadERC1155TokenWithdraw(
                        tokenInfo.tokenAddress,
                        from,
                        to,
                        tokenInfo.id,
                        tokenInfo.amount
                    );
                }
            }
        }
    }

    function processTokensInfo(WinningPlace[] calldata winningPlaces) external view returns(TokenInfo[] memory allTokensInfo, uint256 amountOfLootBoxes) {
        allTokensInfo = new TokenInfo[](MAX_TOKENS_IN_LOOTBOX);
        uint256 lastIndex = 0;

        for (uint256 i = 0; i < winningPlaces.length; ++i) {
            require(winningPlaces[i].placeAmounts > 0, "ExilonNftLootbox: Winning amount");
            amountOfLootBoxes += winningPlaces[i].placeAmounts;

            for (uint256 j = 0; j < winningPlaces[i].prizesInfo.length; ++j) {
                ExilonNftLootboxLibrary.TokenInfo memory currentToken = winningPlaces[i].prizesInfo[
                    i
                ];

                if (currentToken.tokenType == ExilonNftLootboxLibrary.TokenType.ERC20) {
                    require(currentToken.id == 0, "ExilonNftLootbox: ERC20 no id");
                    require(currentToken.amount > 0, "ExilonNftLootbox: ERC20 amount");
                } else if (currentToken.tokenType == ExilonNftLootboxLibrary.TokenType.ERC721) {
                    require(currentToken.amount == 0, "ExilonNftLootbox: ERC721 amount");
                    require(
                        winningPlaces[i].placeAmounts == 1,
                        "ExilonNftLootbox: No multiple winners for ERC721"
                    );

                    require(
                        IERC165(currentToken.tokenAddress).supportsInterface(bytes4(0x80ac58cd)),
                        "ExilonNftLootbox: ERC721 type"
                    );
                } else if (currentToken.tokenType == ExilonNftLootboxLibrary.TokenType.ERC1155) {
                    require(currentToken.amount > 0, "ExilonNftLootbox: ERC1155 amount");

                    require(
                        IERC165(currentToken.tokenAddress).supportsInterface(bytes4(0xd9b67a26)),
                        "ExilonNftLootbox: ERC1155 type"
                    );
                }
                currentToken.amount = currentToken.amount * winningPlaces[i].placeAmounts;

                uint256 index = _findTokenInTokenInfoArray(
                    allTokensInfo,
                    lastIndex,
                    currentToken.tokenAddress,
                    currentToken.id
                );
                if (index != type(uint256).max) {
                    require(
                        currentToken.tokenType != ExilonNftLootboxLibrary.TokenType.ERC721,
                        "ExilonNftLootbox: Multiple ERC721"
                    );
                    allTokensInfo[index].amount += currentToken.amount;
                } else {
                    require(
                        lastIndex < MAX_TOKENS_IN_LOOTBOX,
                        "ExilonNftLootbox: Too many different tokens"
                    );
                    allTokensInfo[lastIndex] = currentToken;

                    ++lastIndex;
                }
            }
        }

        uint256 numberToDecrease = MAX_TOKENS_IN_LOOTBOX - lastIndex;
        assembly { mstore(allTokensInfo, sub(mload(allTokensInfo), numberToDecrease)) }
    }

    function _findTokenInTokenInfoArray(
        ExilonNftLootboxLibrary.TokenInfo[] memory tokensInfo,
        uint256 len,
        address token,
        uint256 id
    ) private pure returns (uint256) {
        for (uint256 i = 0; i < len; ++i) {
            if (tokensInfo[i].tokenAddress == token && tokensInfo[i].id == id) {
                return i;
            }
        }
        return type(uint256).max;
    }
}
