// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "src/interfaces/ICollateralGate.sol";

/// @notice Test file for collateral gating. Lock and unlock just do nothing currently. 

contract TestCollateralGate is ICollateralGate {

    function lock(address _user, uint256 _veYETIToBurn, uint256 _YETIToLock) external override {
        return;
    }

    function unlock(address _user, uint256 _YETIToUnlock) external override {
        return;
    }
}
