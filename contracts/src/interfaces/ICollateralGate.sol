pragma solidity >0.8.0;

interface ICollateralGate {
    function lock(address _user, uint256 _veYETIToBurn, uint256 _YETIToLock) external;
    function unlock(address _user, uint256 _YETIToUnlock) external;
}
