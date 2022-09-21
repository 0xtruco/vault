// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

interface IYetiController {
    function getValidCollateral() external view returns (address[] memory);
    function isWrappedMany(address[] memory _collaterals) external view returns (bool[] memory wrapped);
}

interface IYetiVault {
    function compound() external returns (uint256);
}

contract Compounder {

    IYetiController constant public yetiController = IYetiController(0xcCCCcCccCCCc053fD8D1fF275Da4183c2954dBe3);

    address public owner;

    address public caller;

    // If they are not wrapped in YetiController but need to compound, add to this list
    address[] public extraCollToCompound;

    constructor(address _caller, address _owner) public {
        caller = _caller;
        owner = _owner;
    }

    function callCompound() external {
        require(msg.sender == caller);
        address[] memory validCollateral = yetiController.getValidCollateral();
        bool[] memory wrapped = yetiController.isWrappedMany(validCollateral);
        for (uint i; i < wrapped.length; ++i) {
            if (wrapped[i]) {
                IYetiVault(validCollateral[i]).compound();
            }
        }
        for (uint i; i < extraCollToCompound.length; ++i) {
            if (extraCollToCompound[i] != address(0)) {
                IYetiVault(extraCollToCompound[i]).compound();
            }
        }
    }

    function addToExtraList(address _newColl) external {
        require(msg.sender == owner);
        extraCollToCompound.push(_newColl);
    }

    function addToExtraList(uint256 _removeIndex) external {
        require(msg.sender == owner);
        extraCollToCompound[_removeIndex] = address(0);
    }

    function changeCaller(address _newCaller) external {
        require(msg.sender == owner);
        caller = _newCaller;
    }

    function transferOwnership(address _newOwner) external {
        require(msg.sender == owner);
        owner = _newOwner;
    }

}
