// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.12;

import "./ExilonNftLootboxLibrary.sol";
import "./AccessConnector.sol";

abstract contract FeeSender is AccessConnector {
    address public feeReceiver;

    uint256 public minimalAmountToDistribute = 0.5 ether;

    event FeeSendInfoChange(address newFeeReceiver, uint256 newMinimalAmountToDistribute);

    event CommissionTransfer(address indexed to, uint256 amount);
    event BadCommissionTransfer(address indexed to, uint256 amount);

    constructor(address _feeReceiver) {
        feeReceiver = _feeReceiver;

        emit FeeSendInfoChange(_feeReceiver, minimalAmountToDistribute);
    }

    function processFeeTransferOnFeeReceiver() external onlyAdmin {
        _processFeeTransferOnFeeReceiverPrivate(true);
    }

    function setFeeInfo(address newFeeReceiver, uint256 newMinimalAmountToDistribute)
        external
        onlyAdmin
    {
        feeReceiver = newFeeReceiver;
        minimalAmountToDistribute = newMinimalAmountToDistribute;

        emit FeeSendInfoChange(newFeeReceiver, newMinimalAmountToDistribute);
    }

    function _processFeeTransferOnFeeReceiver() internal {
        _processFeeTransferOnFeeReceiverPrivate(false);
    }

    function _processFeeTransferOnFeeReceiverPrivate(bool force) private {
        address _feeReceiver = feeReceiver;
        uint256 amount = address(this).balance;
        if (amount == 0 || (!force && amount < minimalAmountToDistribute)) {
            return;
        }
        bool success;
        if (force) {
            (success, ) = _feeReceiver.call{value: amount}("");
            require(success, "FeesCalculator: Transfer failed");
        } else {
            require(
                gasleft() >= ExilonNftLootboxLibrary.MAX_GAS_FOR_ETH_TRANSFER,
                "FeesCalculator: Not enough gas"
            );
            (success, ) = _feeReceiver.call{
                value: amount,
                gas: ExilonNftLootboxLibrary.MAX_GAS_FOR_ETH_TRANSFER
            }("");
        }
        if (!success) {
            emit BadCommissionTransfer(_feeReceiver, amount);
        } else {
            emit CommissionTransfer(_feeReceiver, amount);
        }
    }
}
