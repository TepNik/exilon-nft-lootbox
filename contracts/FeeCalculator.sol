// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.11;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import "./pancake-swap/interfaces/IPancakeRouter02.sol";

import "./AccessConnector.sol";

abstract contract FeeCalculator is AccessConnector {
    // public

    address public immutable usdToken;
    IPancakeRouter02 public immutable pancakeRouter;

    uint256 public extraPriceForFront = 500; // 5%

    // private

    address internal immutable _weth;

    // internal

    uint256 internal immutable _oneUsd;

    modifier onlyEOA() {
        require(msg.sender == tx.origin, "FeesCalculator: Only EOA");
        _;
    }

    event ExtraPriceForFrontChange(uint256 newValue);

    event FeesCollected(address indexed user, uint256 bnbAmount, uint256 usdAmount);

    constructor(address _usdToken, IPancakeRouter02 _pancakeRouter) {
        usdToken = _usdToken;
        _oneUsd = 10**IERC20Metadata(_usdToken).decimals();

        pancakeRouter = _pancakeRouter;
        _weth = _pancakeRouter.WETH();

        emit ExtraPriceForFrontChange(extraPriceForFront);
    }

    function setExtraPriceForFront(uint256 newValue) external onlyAdmin {
        require(newValue <= 5_000, "FeesCalculator: Too big percentage"); // 50%
        extraPriceForFront = newValue;

        emit ExtraPriceForFrontChange(newValue);
    }

    function _getBnbAmountToFront(uint256 usdAmount) internal view returns (uint256) {
        return _getBnbAmount((usdAmount * (extraPriceForFront + 10_000)) / 10_000);
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

    function _getBnbAmount(uint256 usdAmount) internal view onlyEOA returns (uint256) {
        if (usdAmount == 0) {
            return 0;
        }
        address[] memory path = new address[](2);
        path[0] = _weth;
        path[1] = usdToken;
        return (pancakeRouter.getAmountsIn(usdAmount, path))[0];
    }
}
