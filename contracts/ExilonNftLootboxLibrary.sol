// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.11;

import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./pancake-swap/interfaces/IPancakeRouter02.sol";

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
        uint256 amount,
        string errorMessage
    );
    event BadERC721TokenWithdraw(
        address indexed token,
        address indexed from,
        address indexed to,
        uint256 id,
        string errorMessage
    );
    event BadERC1155TokenWithdraw(
        address indexed token,
        address indexed from,
        address indexed to,
        uint256 id,
        uint256 amount,
        string errorMessage
    );

    function withdrawToken(
        TokenInfo memory tokenInfo,
        address from,
        address to,
        bool requireSuccess
    ) public {
        if (tokenInfo.tokenType == TokenType.ERC20) {
            if (from == address(this)) {
                if (requireSuccess) {
                    IERC20(tokenInfo.tokenAddress).safeTransfer(to, tokenInfo.amount);
                } else {
                    (bool success, bytes memory result) = tokenInfo.tokenAddress.call{
                        gas: MAX_GAS_FOR_TRANSFER
                    }(abi.encodeWithSelector(IERC20.transfer.selector, to, tokenInfo.amount));
                    if (!success) {
                        emit BadERC20TokenWithdraw(
                            tokenInfo.tokenAddress,
                            from,
                            to,
                            tokenInfo.amount,
                            _getRevertMsg(result)
                        );
                    }
                }
            } else {
                if (requireSuccess) {
                    IERC20(tokenInfo.tokenAddress).safeTransferFrom(from, to, tokenInfo.amount);
                } else {
                    (bool success, bytes memory result) = tokenInfo.tokenAddress.call{
                        gas: MAX_GAS_FOR_TRANSFER
                    }(
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
                            tokenInfo.amount,
                            _getRevertMsg(result)
                        );
                    }
                }
            }
        } else if (tokenInfo.tokenType == TokenType.ERC721) {
            if (requireSuccess) {
                IERC721(tokenInfo.tokenAddress).safeTransferFrom(from, to, tokenInfo.id);
            } else {
                (bool success, bytes memory result) = tokenInfo.tokenAddress.call{
                    gas: MAX_GAS_FOR_TRANSFER
                }(
                    abi.encodeWithSignature(
                        "safeTransferFrom(address,address,uint256)",
                        from,
                        to,
                        tokenInfo.id
                    )
                );
                if (!success) {
                    emit BadERC721TokenWithdraw(
                        tokenInfo.tokenAddress,
                        from,
                        to,
                        tokenInfo.id,
                        _getRevertMsg(result)
                    );
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
                (bool success, bytes memory result) = tokenInfo.tokenAddress.call{
                    gas: MAX_GAS_FOR_TRANSFER
                }(
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
                        tokenInfo.amount,
                        _getRevertMsg(result)
                    );
                }
            }
        }
    }

    function transferFundsToFundsHolder(
        TokenInfo[] memory allTokensInfo,
        address fundsHolder,
        uint256 id,
        mapping(uint256 => mapping(address => uint256)) storage totalSharesOfERC20
    ) external {
        for (uint256 i = 0; i < allTokensInfo.length; ++i) {
            withdrawToken(allTokensInfo[i], msg.sender, fundsHolder, true);

            if (allTokensInfo[i].tokenType == TokenType.ERC20) {
                totalSharesOfERC20[id][allTokensInfo[i].tokenAddress] = allTokensInfo[i].amount;
            }
        }
    }

    function getRandomNumber(uint256 nonce, uint256 upperLimit) external view returns (uint256) {
        return
            uint256(
                keccak256(
                    abi.encodePacked(
                        block.timestamp,
                        block.number,
                        msg.sender,
                        nonce,
                        blockhash(block.number - 1),
                        blockhash(block.number - 2),
                        block.coinbase,
                        block.difficulty
                    )
                )
            ) % upperLimit;
    }

    function processTokensInfo(WinningPlace[] calldata winningPlaces)
        external
        view
        returns (TokenInfo[] memory allTokensInfo, uint256 amountOfLootBoxes)
    {
        allTokensInfo = new TokenInfo[](MAX_TOKENS_IN_LOOTBOX);
        uint256 lastIndex = 0;

        for (uint256 i = 0; i < winningPlaces.length; ++i) {
            require(winningPlaces[i].placeAmounts > 0, "ExilonNftLootbox: Winning amount");
            amountOfLootBoxes += winningPlaces[i].placeAmounts;

            for (uint256 j = 0; j < winningPlaces[i].prizesInfo.length; ++j) {
                ExilonNftLootboxLibrary.TokenInfo memory currentToken = winningPlaces[i].prizesInfo[
                    j
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
        assembly {
            mstore(allTokensInfo, sub(mload(allTokensInfo), numberToDecrease))
        }
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

    function getWinningIndex(WinningPlace[] memory restPrizes, uint256 randomNumber)
        external
        pure
        returns (uint256 winningIndex)
    {
        winningIndex = type(uint256).max;
        uint256 amountPassed;
        for (uint256 j = 0; j < restPrizes.length && winningIndex == type(uint256).max; ++j) {
            if (restPrizes[j].placeAmounts >= randomNumber + 1 - amountPassed) {
                winningIndex = j;
            }
            amountPassed += restPrizes[j].placeAmounts;
        }
        require(winningIndex != type(uint256).max, "ExilonNftLootbox: Random generator");
    }

    function removeWinningPlace(
        WinningPlace[] memory restPrizes,
        uint256 id,
        uint256 winningIndex,
        mapping(uint256 => WinningPlace[]) storage prizes
    ) external returns (WinningPlace[] memory) {
        restPrizes[winningIndex].placeAmounts -= 1;
        prizes[id][winningIndex].placeAmounts -= 1;
        if (restPrizes[winningIndex].placeAmounts == 0) {
            uint256 len = restPrizes.length;
            if (winningIndex < len - 1) {
                prizes[id][winningIndex] = prizes[id][len - 1];
                restPrizes[winningIndex] = restPrizes[len - 1];
            }

            prizes[id].pop();

            assembly {
                mstore(restPrizes, sub(mload(restPrizes), 1))
            }
        }

        return restPrizes;
    }

    function _getRevertMsg(bytes memory revertData)
        private
        pure
        returns (string memory errorMessage)
    {
        // revert data format:
        // 4 bytes - Function selector for Error(string)
        // 32 bytes - Data offset
        // 32 bytes - String length
        // other - String data

        // If the revertData length is less than 68, then the transaction failed silently (without a revert message)
        if (revertData.length <= 68) return "";

        uint256 index = revertData.length - 1;
        while (index > 68 && revertData[index] == bytes1(0)) {
            index--;
        }
        uint256 numberOfZeroElements = revertData.length - 1 - index;

        bytes memory rawErrorMessage = new bytes(revertData.length - 68 - numberOfZeroElements);

        for (uint256 i = 0; i < revertData.length - 68 - numberOfZeroElements; ++i) {
            rawErrorMessage[i] = revertData[i + 68];
        }
        errorMessage = string(rawErrorMessage);
    }
}
