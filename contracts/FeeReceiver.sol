// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "./AccessConnector.sol";

contract FeeReceiver is AccessConnector {
    using SafeERC20 for IERC20;

    address[] public feeRecipients;
    uint256[] public feeRecipientAmounts;

    uint256 public totalShares;

    uint256 public minimalAmountToDistribute = 1 ether;

    event FeeRecipientsChange(
        address[] feeRecipients,
        uint256[] feeRecipientAmounts,
        uint256 totalShares
    );
    event Distribution(address[] feeRecipients, uint256[] amounts);

    event MinimalAmountToDistributeChange(uint256 newValue);

    constructor(
        address[] memory _feeRecipients,
        uint256[] memory _feeRecipientAmounts,
        IAccess _accessControl
    ) AccessConnector(_accessControl) {
        _setFeeRecipientParameters(_feeRecipients, _feeRecipientAmounts);

        emit MinimalAmountToDistributeChange(minimalAmountToDistribute);
    }

    receive() external payable nonReentrant {
        _distribute(false);
    }

    function distribute() external nonReentrant {
        _distribute(true);
    }

    function setFeeRecipientParameters(
        address[] memory _feeRecipients,
        uint256[] memory _feeRecipientAmounts
    ) external onlyAdmin {
        _setFeeRecipientParameters(_feeRecipients, _feeRecipientAmounts);
    }

    function withdrawToken(address token, uint256 amount) external nonReentrant onlyAdmin {
        uint256 balance;
        if (token == address(0)) {
            balance = address(this).balance;
        } else {
            balance = IERC20(token).balanceOf(address(this));
        }

        if (balance == 0) {
            return;
        }

        if (amount == 0 || amount > balance) {
            amount = balance;
        }

        if (token == address(0)) {
            (bool success, ) = msg.sender.call{value: amount}("");
            require(success, "FeeReceiver: Withdraw failed");
        } else {
            IERC20(token).safeTransfer(msg.sender, amount);
        }
    }

    function _distribute(bool isForce) private {
        uint256 amount = address(this).balance;
        if (amount == 0) {
            return;
        }

        if (!isForce && amount < minimalAmountToDistribute) {
            return;
        }

        address[] memory _feeRecipients = feeRecipients;
        uint256[] memory _feeRecipientAmounts = feeRecipientAmounts;
        uint256 _totalShares = totalShares;
        uint256 restAmount = amount;
        for (uint256 i = 0; i < _feeRecipients.length; ++i) {
            uint256 amountNow;
            if (i < _feeRecipients.length - 1) {
                amountNow = (amount * _feeRecipientAmounts[i]) / _totalShares;
                restAmount -= amountNow;
            } else {
                amountNow = restAmount;
            }
            _feeRecipientAmounts[i] = amountNow;

            (bool success, ) = _feeRecipients[i].call{value: amountNow}("");
            require(success, "FeeReceiver: Transfer failed");
        }

        emit Distribution(_feeRecipients, _feeRecipientAmounts);
    }

    function setMinimalAmountToDistribute(uint256 newValue) external onlyAdmin {
        minimalAmountToDistribute = newValue;

        emit MinimalAmountToDistributeChange(newValue);
    }

    function _setFeeRecipientParameters(
        address[] memory _feeRecipients,
        uint256[] memory _feeRecipientAmounts
    ) private {
        require(
            _feeRecipients.length > 0 && _feeRecipients.length == _feeRecipientAmounts.length,
            "FeeReceiver: Bad length"
        );

        uint256 _totalShares;
        for (uint256 i = 0; i < _feeRecipients.length; ++i) {
            require(_feeRecipientAmounts[i] > 0, "FeeReceiver: Bad amounts");

            _totalShares += _feeRecipientAmounts[i];
        }
        require(_totalShares > 0, "FeeReceiver: Bad shares");
        totalShares = _totalShares;
        feeRecipients = _feeRecipients;
        feeRecipientAmounts = _feeRecipientAmounts;

        emit FeeRecipientsChange(_feeRecipients, _feeRecipientAmounts, _totalShares);
    }
}
