// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.11;

import "./ExilonNftLootboxLibrary.sol";
import "./AccessConnector.sol";

abstract contract FeeSender is AccessConnector {
    address public feeReceiver;

    event FeeReceiverChange(address newValue);

    event CommissionTransfer(address indexed to, uint256 amount);
    event BadCommissionTransfer(address indexed to, uint256 amount);

    constructor(address _feeReceiver) {
        feeReceiver = _feeReceiver;

        emit FeeReceiverChange(_feeReceiver);
    }

    function processFeeTransferOnFeeReceiver() external onlyAdmin {
        _processFeeTransferOnFeeReceiverPrivate(true);
    }

    function setFeeReceiver(address newValue) external onlyAdmin {
        feeReceiver = newValue;

        emit FeeReceiverChange(newValue);
    }

    function _processFeeTransferOnFeeReceiver() internal {
        _processFeeTransferOnFeeReceiverPrivate(false);
    }

    function _processFeeTransferOnFeeReceiverPrivate(bool force) private {
        address _feeReceiver = feeReceiver;
        uint256 amount = address(this).balance;
        if (amount == 0) {
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
