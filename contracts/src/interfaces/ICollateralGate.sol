pragma solidity >0.8.0;

interface ICollateralGate {
    function lock(address _user, uint _collateralAmount, address _origin) external;
    function unlock(address _user, uint _collateralAmount, address _origin) external;
}
