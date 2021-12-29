// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.11;

import "@openzeppelin/contracts/access/AccessControl.sol";

import "./pancake-swap/interfaces/IPancakeRouter02.sol";

import "./ExilonNftLootboxLibrary.sol";

contract FeesCalculator is AccessControl {
    // public

    address public feeReceiver;

    address public immutable usdToken;
    IPancakeRouter02 public immutable pancakeRouter;

    uint256 public extraPriceForFront = 500; // 5%

    // private

    address private immutable _weth;

    modifier onlyEOA() {
        require(msg.sender == tx.origin, "FeesCalculator: Only EOA");
        _;
    }

    event FeeReceiverChange(address newValue);
    event ExtraPriceForFrontChange(uint256 newValue);

    event FeesCollected(address indexed user, uint256 bnbAmount, uint256 usdAmount);
    event CommissionTransfer(address indexed to, uint256 amount);

    event BadCommissionTransfer(address indexed to, uint256 amount);

    constructor(
        address _usdToken,
        IPancakeRouter02 _pancakeRouter,
        address _feeReceiver
    ) {
        usdToken = _usdToken;
        pancakeRouter = _pancakeRouter;

        _weth = _pancakeRouter.WETH();

        feeReceiver = _feeReceiver;

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);

        emit FeeReceiverChange(_feeReceiver);
        emit ExtraPriceForFrontChange(extraPriceForFront);
    }

    function processFeeTransferOnFeeReceiver() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _processFeeTransferOnFeeReceiver();
    }

    function setFeeReceiver(address newValue) external onlyRole(DEFAULT_ADMIN_ROLE) {
        feeReceiver = newValue;

        emit FeeReceiverChange(newValue);
    }

    function setExtraPriceForFront(uint256 newValue) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newValue <= 5_000, "FeesCalculator: Too big percentage"); // 50%
        extraPriceForFront = newValue;

        emit ExtraPriceForFrontChange(newValue);
    }

    function _getBnbAmountToFront(uint256 usdAmount) internal view returns (uint256) {
        return _getBnbAmount((usdAmount * (extraPriceForFront + 10_000)) / 10_000);
    }

    function _processFeeTransferOnFeeReceiver() internal {
        address _feeReceiver = feeReceiver;
        uint256 amount = address(this).balance;
        require(
            gasleft() >= ExilonNftLootboxLibrary.MAX_GAS_FOR_ETH_TRANSFER,
            "ExilonNftLootboxLibrary: Not enough gas"
        );
        (bool success, ) = _feeReceiver.call{
            value: amount,
            gas: ExilonNftLootboxLibrary.MAX_GAS_FOR_ETH_TRANSFER
        }("");
        if (!success) {
            emit BadCommissionTransfer(_feeReceiver, amount);
        } else {
            emit CommissionTransfer(_feeReceiver, amount);
        }
    }

    function _checkFees(uint256 amount) internal returns (uint256 bnbAmount) {
        bnbAmount = _getBnbAmount(amount);

        require(msg.value >= bnbAmount, "FeesCalculator: Not enough bnb");

        uint256 amountBack = msg.value - bnbAmount;
        if (amountBack > 0) {
            (bool success, ) = msg.sender.call{value: amountBack}("");
            require(success, "FeesCalculator: Failed transfer back");
        }

        emit FeesCollected(msg.sender, bnbAmount, amount);
    }

    function _getBnbAmount(uint256 amount) private view returns (uint256) {
        if (amount == 0) {
            return 0;
        }
        address[] memory path = new address[](2);
        path[0] = _weth;
        path[1] = usdToken;
        return (pancakeRouter.getAmountsIn(amount, path))[0];
    }
}
