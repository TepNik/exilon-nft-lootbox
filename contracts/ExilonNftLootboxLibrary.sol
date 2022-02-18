// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.11;

import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

import "./pancake-swap/interfaces/IPancakeRouter02.sol";

import "./interfaces/IExilon.sol";
import "./interfaces/IExilonNftLootboxMain.sol";
import "./interfaces/IPriceHolder.sol";
import "./interfaces/IFundsHolder.sol";

library ExilonNftLootboxLibrary {
    using SafeERC20 for IERC20;

    enum TokenType {
        ERC20,
        ERC721,
        ERC1155
    }

    enum LootBoxType {
        DEFAULT,
        MEGA_LOOTBOX_RESERVE,
        MEGA_LOOTBOX_NO_RESERVE
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
    uint256 public constant MAX_GAS_FOR_TOKEN_TRANSFER = 1_200_000;
    uint256 public constant MAX_GAS_FOR_ETH_TRANSFER = 500_000;

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
    ) public returns (bool) {
        if (tokenInfo.tokenType == TokenType.ERC20) {
            if (from == address(this)) {
                if (requireSuccess) {
                    IERC20(tokenInfo.tokenAddress).safeTransfer(to, tokenInfo.amount);
                    return true;
                } else {
                    require(
                        gasleft() >= MAX_GAS_FOR_TOKEN_TRANSFER,
                        "ExilonNftLootboxLibrary: Not enough gas"
                    );
                    (bool success, bytes memory result) = tokenInfo.tokenAddress.call{
                        gas: MAX_GAS_FOR_TOKEN_TRANSFER
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
                    return success;
                }
            } else {
                if (requireSuccess) {
                    IERC20(tokenInfo.tokenAddress).safeTransferFrom(from, to, tokenInfo.amount);
                    return true;
                } else {
                    require(
                        gasleft() >= MAX_GAS_FOR_TOKEN_TRANSFER,
                        "ExilonNftLootboxLibrary: Not enough gas"
                    );
                    (bool success, bytes memory result) = tokenInfo.tokenAddress.call{
                        gas: MAX_GAS_FOR_TOKEN_TRANSFER
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
                    return success;
                }
            }
        } else if (tokenInfo.tokenType == TokenType.ERC721) {
            if (requireSuccess) {
                IERC721(tokenInfo.tokenAddress).safeTransferFrom(from, to, tokenInfo.id);
                return true;
            } else {
                require(
                    gasleft() >= MAX_GAS_FOR_TOKEN_TRANSFER,
                    "ExilonNftLootboxLibrary: Not enough gas"
                );
                (bool success, bytes memory result) = tokenInfo.tokenAddress.call{
                    gas: MAX_GAS_FOR_TOKEN_TRANSFER
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
                return success;
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
                return true;
            } else {
                require(
                    gasleft() >= MAX_GAS_FOR_TOKEN_TRANSFER,
                    "ExilonNftLootboxLibrary: Not enough gas"
                );
                (bool success, bytes memory result) = tokenInfo.tokenAddress.call{
                    gas: MAX_GAS_FOR_TOKEN_TRANSFER
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
                return success;
            }
        } else {
            revert("ExilonNftLootboxLibrary: Wrong type of token");
        }
    }

    struct processMergeInfoInputStruct {
        uint256 idFrom;
        uint256 idTo;
        address tokenAddress;
        uint256 balanceBefore;
        address fundsHolderTo;
        ExilonNftLootboxLibrary.WinningPlace[] winningPlacesFrom;
    }

    function processMergeInfo(
        processMergeInfoInputStruct memory input,
        mapping(uint256 => mapping(address => uint256)) storage totalSharesOfERC20,
        mapping(uint256 => WinningPlace[]) storage _prizes
    ) external {
        uint256 totalSharesTo = totalSharesOfERC20[input.idTo][input.tokenAddress];
        uint256 totalSharesFrom = totalSharesOfERC20[input.idFrom][input.tokenAddress];
        if (totalSharesTo == 0) {
            totalSharesOfERC20[input.idTo][input.tokenAddress] = totalSharesFrom;
        } else {
            uint256 balanceAfter = IERC20(input.tokenAddress).balanceOf(input.fundsHolderTo);

            require(
                balanceAfter > input.balanceBefore,
                "ExilonNftLootboxMaster: Merge balance error"
            );
            uint256 newSharesAmount = (balanceAfter * totalSharesTo) /
                input.balanceBefore -
                totalSharesTo;
            totalSharesOfERC20[input.idTo][input.tokenAddress] = totalSharesTo + newSharesAmount;

            for (uint256 i = 0; i < input.winningPlacesFrom.length; ++i) {
                for (uint256 j = 0; j < input.winningPlacesFrom[i].prizesInfo.length; ++j) {
                    if (
                        input.winningPlacesFrom[i].prizesInfo[j].tokenAddress == input.tokenAddress
                    ) {
                        _prizes[input.idFrom][i].prizesInfo[j].amount =
                            (input.winningPlacesFrom[i].prizesInfo[j].amount * newSharesAmount) /
                            totalSharesFrom;
                    }
                }
            }
        }
    }

    function mergeWinningPrizeInfo(
        uint256 idFrom,
        uint256 idTo,
        uint256 lengthTo,
        uint256 lengthFrom,
        address creatorFrom,
        mapping(uint256 => WinningPlace[]) storage _prizes,
        mapping(uint256 => mapping(uint256 => address)) storage _winningPlaceCreator
    ) external {
        for (uint256 i = lengthFrom; i > 0; --i) {
            _prizes[idTo].push(_prizes[idFrom][i - 1]);
            _prizes[idFrom].pop();
            _winningPlaceCreator[idTo][lengthTo] = creatorFrom;
            ++lengthTo;
        }
    }

    function transferFundsToFundsHolder(
        TokenInfo[] memory allTokensInfo,
        address fundsHolder,
        uint256 id,
        address exilon,
        mapping(uint256 => mapping(address => uint256)) storage totalSharesOfERC20
    ) external {
        for (uint256 i = 0; i < allTokensInfo.length; ++i) {
            if (
                allTokensInfo[i].tokenAddress == exilon &&
                AccessControl(exilon).hasRole(bytes32(0), address(this)) &&
                !IExilon(exilon).isExcludedFromPayingFees(fundsHolder)
            ) {
                IExilon(exilon).excludeFromPayingFees(fundsHolder);
            }

            withdrawToken(allTokensInfo[i], msg.sender, fundsHolder, true);

            if (allTokensInfo[i].tokenType == TokenType.ERC20) {
                totalSharesOfERC20[id][allTokensInfo[i].tokenAddress] = allTokensInfo[i].amount;
            }
        }
    }

    function getRandomNumber(uint256 nonce, uint256 upperLimit) public view returns (uint256) {
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

    function processTokensInfo(WinningPlace[] memory winningPlaces)
        public
        view
        returns (TokenInfo[] memory allTokensInfo, uint256 amountOfLootBoxes)
    {
        allTokensInfo = new TokenInfo[](MAX_TOKENS_IN_LOOTBOX);
        uint256 lastIndex = 0;

        for (uint256 i = 0; i < winningPlaces.length; ++i) {
            require(winningPlaces[i].placeAmounts > 0, "ExilonNftLootboxLibrary: Winning amount");
            amountOfLootBoxes += winningPlaces[i].placeAmounts;

            for (uint256 j = 0; j < winningPlaces[i].prizesInfo.length; ++j) {
                ExilonNftLootboxLibrary.TokenInfo memory currentToken = winningPlaces[i].prizesInfo[
                    j
                ];

                if (currentToken.tokenType == ExilonNftLootboxLibrary.TokenType.ERC20) {
                    require(currentToken.id == 0, "ExilonNftLootboxLibrary: ERC20 no id");
                    require(currentToken.amount > 0, "ExilonNftLootboxLibrary: ERC20 amount");
                } else if (currentToken.tokenType == ExilonNftLootboxLibrary.TokenType.ERC721) {
                    require(currentToken.amount == 0, "ExilonNftLootboxLibrary: ERC721 amount");
                    require(
                        winningPlaces[i].placeAmounts == 1,
                        "ExilonNftLootboxLibrary: No multiple winners for ERC721"
                    );

                    require(
                        IERC165(currentToken.tokenAddress).supportsInterface(bytes4(0x80ac58cd)),
                        "ExilonNftLootboxLibrary: ERC721 type"
                    );
                } else if (currentToken.tokenType == ExilonNftLootboxLibrary.TokenType.ERC1155) {
                    require(currentToken.amount > 0, "ExilonNftLootboxLibrary: ERC1155 amount");

                    require(
                        IERC165(currentToken.tokenAddress).supportsInterface(bytes4(0xd9b67a26)),
                        "ExilonNftLootboxLibrary: ERC1155 type"
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
                        "ExilonNftLootboxLibrary: Multiple ERC721"
                    );
                    allTokensInfo[index].amount += currentToken.amount;
                } else {
                    require(
                        lastIndex < MAX_TOKENS_IN_LOOTBOX,
                        "ExilonNftLootboxLibrary: Too many different tokens"
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
        require(winningIndex != type(uint256).max, "ExilonNftLootboxLibrary: Random generator");
    }

    struct refundWinningPlaceToOwnerInput {
        uint256 id;
        uint256 index;
        address creator;
        WinningPlace winningPlace;
        LootBoxType lootboxType;
        address fundsHolder;
        IPriceHolder priceHolder;
        IExilonNftLootboxMain exilonNftLootboxMain;
    }

    function refundWinningPlaceToOwner(
        refundWinningPlaceToOwnerInput memory input,
        WinningPlace[] storage _prizes,
        mapping(address => uint256) storage _totalSharesOfERC20,
        mapping(uint256 => address) storage winningPlaceCreator
    ) external returns (TokenInfo[] memory) {
        WinningPlace[] memory singletonArray = new WinningPlace[](1);
        singletonArray[0] = input.winningPlace;
        (TokenInfo[] memory allTokensInfo, ) = processTokensInfo(singletonArray);

        for (uint256 i = 0; i < allTokensInfo.length; ++i) {
            uint256 balanceBefore;
            uint256 sharesBefore;
            if (allTokensInfo[i].tokenType == ExilonNftLootboxLibrary.TokenType.ERC20) {
                balanceBefore = IERC20(allTokensInfo[i].tokenAddress).balanceOf(input.fundsHolder);

                sharesBefore = _totalSharesOfERC20[allTokensInfo[i].tokenAddress];
                _totalSharesOfERC20[allTokensInfo[i].tokenAddress] =
                    sharesBefore -
                    allTokensInfo[i].amount;
                allTokensInfo[i].amount = (allTokensInfo[i].amount * balanceBefore) / sharesBefore;
            }
        }

        uint256 length = _prizes.length;
        if (input.index < length - 1) {
            _prizes[input.index] = _prizes[length - 1];
            if (input.lootboxType != LootBoxType.DEFAULT) {
                winningPlaceCreator[input.index] = winningPlaceCreator[length - 1];
            }
        }
        if (input.lootboxType != LootBoxType.DEFAULT) {
            delete winningPlaceCreator[length - 1];
        }
        _prizes.pop();

        if (input.lootboxType == ExilonNftLootboxLibrary.LootBoxType.MEGA_LOOTBOX_RESERVE) {
            input.exilonNftLootboxMain.refundToUser(
                input.creator,
                input.creator,
                0,
                input.priceHolder.defaultOpeningPrice(input.id) * input.winningPlace.placeAmounts
            );
        }

        input.exilonNftLootboxMain.burn(address(this), input.id, input.winningPlace.placeAmounts);

        return allTokensInfo;
    }

    function removeWinningPlace(
        WinningPlace[] memory restPrizes,
        uint256 winningIndex,
        WinningPlace[] storage winningPlaces,
        bool needToPeplaceCreators,
        mapping(uint256 => address) storage winningPlaceCreator
    ) external returns (WinningPlace[] memory) {
        restPrizes[winningIndex].placeAmounts -= 1;
        winningPlaces[winningIndex].placeAmounts -= 1;
        if (restPrizes[winningIndex].placeAmounts == 0) {
            uint256 len = restPrizes.length;
            if (winningIndex < len - 1) {
                winningPlaces[winningIndex] = winningPlaces[len - 1];
                restPrizes[winningIndex] = restPrizes[len - 1];

                if (needToPeplaceCreators) {
                    winningPlaceCreator[winningIndex] = winningPlaceCreator[len - 1];
                }
            }

            delete winningPlaceCreator[len - 1];
            winningPlaces.pop();

            assembly {
                mstore(restPrizes, sub(mload(restPrizes), 1))
            }
        }

        return restPrizes;
    }

    function getUsdPriceOfAToken(
        IPancakeRouter02 pancakeRouter,
        address usdToken,
        address weth,
        address token,
        uint256 amount
    ) public view returns (uint256) {
        if (amount == 0) {
            return 0;
        }

        if (token == usdToken) {
            return amount;
        } else if (token == weth) {
            address[] memory path = new address[](2);
            path[0] = weth;
            path[1] = usdToken;
            return (pancakeRouter.getAmountsOut(amount, path))[1];
        } else {
            address[] memory path = new address[](3);
            path[0] = token;
            path[1] = weth;
            path[2] = usdToken;
            return (pancakeRouter.getAmountsOut(amount, path))[2];
        }
    }

    function sendTokenCarefully(
        IERC20 token,
        address user,
        uint256 amount,
        bool reequireSuccess
    )
        external
        returns (
            bool,
            uint256,
            string memory
        )
    {
        if (amount == 0) {
            return (true, 0, "");
        }

        uint256 balance;
        if (address(token) == address(0)) {
            balance = address(this).balance;
        } else {
            balance = token.balanceOf(address(this));
        }

        if (amount > balance) {
            amount = balance;
        }

        if (amount > 0) {
            bool success;
            bytes memory data;
            if (address(token) == address(0)) {
                require(
                    gasleft() >= MAX_GAS_FOR_ETH_TRANSFER,
                    "ExilonNftLootboxLibrary: Not enough gas"
                );
                (success, data) = user.call{gas: MAX_GAS_FOR_ETH_TRANSFER, value: amount}("");
            } else {
                require(
                    gasleft() >= MAX_GAS_FOR_TOKEN_TRANSFER,
                    "ExilonNftLootboxLibrary: Not enough gas"
                );
                (success, data) = address(token).call{gas: MAX_GAS_FOR_TOKEN_TRANSFER}(
                    abi.encodeWithSelector(IERC20.transfer.selector, user, amount)
                );
            }

            if (reequireSuccess) {
                require(success, "ExilonNftLootboxLibrary: Carefull token transfer failed");
                return (true, amount, "");
            } else {
                if (success) {
                    return (success, amount, "");
                } else {
                    return (success, amount, _getRevertMsg(data));
                }
            }
        } else {
            return (true, 0, "");
        }
    }

    struct getWinningAmountInputStruct {
        uint256 totalShares;
        uint256 prizeInfoAmount;
        address tokenAddress;
        address fundsHolder;
        uint256 winningPlaceAmounts;
        uint256 nonce;
        uint256 minRandomPercentage;
        uint256 maxRandomPercentage;
        uint256 powParameter;
    }

    struct getWinningAmountOutputStruct {
        uint256 rawAmount;
        uint256 sharesAmount;
        uint256 newPrizeInfoAmount;
    }

    function getWinningAmount(getWinningAmountInputStruct memory input)
        external
        view
        returns (getWinningAmountOutputStruct memory output)
    {
        uint256 totalAmountOnFundsHolder = IERC20(input.tokenAddress).balanceOf(input.fundsHolder);

        uint256 totalAmountOfSharesForWinnginPlace = input.prizeInfoAmount *
            input.winningPlaceAmounts;
        uint256 totalAmountOfFundsForWinningPlace = (totalAmountOnFundsHolder *
            totalAmountOfSharesForWinnginPlace) / input.totalShares;

        if (input.winningPlaceAmounts == 1) {
            return
                getWinningAmountOutputStruct({
                    rawAmount: totalAmountOfFundsForWinningPlace,
                    sharesAmount: totalAmountOfSharesForWinnginPlace,
                    newPrizeInfoAmount: input.prizeInfoAmount
                });
        }

        uint256 randomNumber = getRandomNumber(input.nonce, 1000);

        (uint256 minWinningAmount, uint256 maxWinningAmount) = _getMinAndMaxAmount(
            totalAmountOfFundsForWinningPlace,
            input.winningPlaceAmounts,
            input.minRandomPercentage,
            input.maxRandomPercentage
        );
        output.rawAmount =
            minWinningAmount +
            (((maxWinningAmount - minWinningAmount) * randomNumber**input.powParameter) /
                1000**input.powParameter);

        (uint256 minSharesAmount, uint256 maxSharesAmount) = _getMinAndMaxAmount(
            totalAmountOfSharesForWinnginPlace,
            input.winningPlaceAmounts,
            input.minRandomPercentage,
            input.maxRandomPercentage
        );
        output.sharesAmount =
            minSharesAmount +
            (((maxSharesAmount - minSharesAmount) * randomNumber**input.powParameter) /
                1000**input.powParameter);

        output.newPrizeInfoAmount =
            (totalAmountOfSharesForWinnginPlace - output.sharesAmount) /
            (input.winningPlaceAmounts - 1);
    }

    function _getMinAndMaxAmount(
        uint256 total,
        uint256 winningPlaceAmounts,
        uint256 minRandomPercentage,
        uint256 maxRandomPercentage
    ) private pure returns (uint256 min, uint256 max) {
        min = (total * minRandomPercentage) / (winningPlaceAmounts * 10_000);
        max = (total * maxRandomPercentage) / (winningPlaceAmounts * 10_000);

        uint256 minimalReservationsForOtherUsers = (total * 5_000 * (winningPlaceAmounts - 1)) /
            (winningPlaceAmounts * 10_000);

        if (max > total - minimalReservationsForOtherUsers) {
            max = total - minimalReservationsForOtherUsers;
        }

        if (min > max) {
            min = max;
        }
    }

    struct addTokenInfoToAllTokensArrayInputStruct {
        TokenInfo prizeInfo;
        uint256 balanceBefore;
        uint256 lastIndex;
        TokenInfo[] successWithdrawTokens;
    }

    function addTokenInfoToAllTokensArray(addTokenInfoToAllTokensArrayInputStruct memory input)
        external
        view
        returns (
            TokenInfo[] memory,
            uint256,
            uint256
        )
    {
        if (input.prizeInfo.tokenType == TokenType.ERC20) {
            uint256 balanceAfter = IERC20(input.prizeInfo.tokenAddress).balanceOf(msg.sender);
            input.prizeInfo.amount = balanceAfter - input.balanceBefore;
        }

        uint256 index = _findTokenInTokenInfoArray(
            input.successWithdrawTokens,
            input.lastIndex,
            input.prizeInfo.tokenAddress,
            input.prizeInfo.id
        );
        if (index != type(uint256).max) {
            input.successWithdrawTokens[index].amount += input.prizeInfo.amount;
        } else {
            input.successWithdrawTokens[input.lastIndex] = input.prizeInfo;

            ++input.lastIndex;
        }

        return (input.successWithdrawTokens, input.lastIndex, input.prizeInfo.amount);
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

        uint256 errorLength = revertData.length - 68 - numberOfZeroElements;
        bytes memory rawErrorMessage = new bytes(errorLength);

        for (uint256 i = 0; i < errorLength; ++i) {
            rawErrorMessage[i] = revertData[i + 68];
        }
        errorMessage = string(rawErrorMessage);
    }
}
