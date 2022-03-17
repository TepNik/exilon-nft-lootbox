// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.12;

import "@openzeppelin/contracts/proxy/Clones.sol";

import "./FundsHolder.sol";
import "./interfaces/IFundsHolderFactory.sol";

contract FundsHolderFactory is IFundsHolderFactory {
    // public

    address public masterContract;
    address public immutable fundsHolderMaster;

    modifier onlyMaster() {
        require(msg.sender == masterContract, "FundsHolderFactory: Not master");
        _;
    }

    event DeployedNewFundsHolder(FundsHolder fundsHolder);

    constructor() {
        FundsHolder _fundsHolderMaster = new FundsHolder();
        _fundsHolderMaster.init(address(this));
        fundsHolderMaster = address(_fundsHolderMaster);
    }

    function init() external {
        require(masterContract == address(0), "FundsHolderFactory: Has already initialized");
        masterContract = msg.sender;
    }

    function deployNewContract() external override onlyMaster returns (address) {
        FundsHolder fundsHolder = FundsHolder(Clones.clone(fundsHolderMaster));
        fundsHolder.init(msg.sender);

        emit DeployedNewFundsHolder(fundsHolder);

        return address(fundsHolder);
    }
}
