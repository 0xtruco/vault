// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import {IERC20} from "./interfaces/IERC20.sol";

interface IYetiController {
    function getValidCollateral() external view returns (address[] memory);
    function isWrappedMany(address[] memory _collaterals) external view returns (bool[] memory wrapped);
}

interface IYetiVault {
    function compound() external returns (uint256);
}

interface IRouter {
    function fullTx(
        address _startingTokenAddress,
        address _endingTokenAddress,
        uint256 _amount,
        uint256 _minSwapAmount
        ) external returns (uint256 amountOut);
}

contract Compounder {

    IYetiController constant public yetiController = IYetiController(0xcCCCcCccCCCc053fD8D1fF275Da4183c2954dBe3);

    address constant public yusd = 0x111111111111ed1D73f860F57b2798b683f2d325;

    address public owner;

    address public caller;

    IRouter public router;

    // If they are not wrapped in YetiController but need to compound, add to this list
    address[] public extraCollToCompound;

    address[] public collateralSellList;

    modifier _onlyOwner() {
        require(msg.sender == owner, "OnlyOwner");
        _;
    }

    modifier _onlyCaller() {
        require(msg.sender == caller, "OnlyCaller");
        _;
    }

    constructor(address _caller, address _owner, address _router) public {
        caller = _caller;
        owner = _owner;
        router = IRouter(_router);
        address[] memory validCollateral = yetiController.getValidCollateral();
        bool[] memory wrapped = yetiController.isWrappedMany(validCollateral);
        for (uint i; i < wrapped.length; ++i) {
            if (wrapped[i]) {
                collateralSellList.push(validCollateral[i]);
            }
        }
    }

    // Calls compound on valid wrapped collateral + any extra
    function callCompound() external _onlyCaller {
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

    function transferERC20(address _token, uint256 _amount, address _recipient) external _onlyCaller {
        IERC20(_token).transfer(_recipient, _amount);
    }

    // Sell from start to end in the collateral sell list. 
    // Assumes route exists for all indices
    function sellThroughRouter(uint256 _startIndex, uint256 _endIndex) external _onlyCaller returns (uint256 yusdGained) {
        if (_endIndex == 0) {
            _endIndex = collateralSellList.length;
        }
        for (uint i = _startIndex; i < _endIndex; ++i) {
            address collateral = collateralSellList[i];
            if (collateral != address(0)) {
                uint256 balance = IERC20(collateral).balanceOf(address(this));
                IERC20(collateral).approve(address(router), balance);
                yusdGained += router.fullTx(collateral, yusd, balance, 1);
            }
        }
    }

    function addToCollateralSellList(address _newColl) external _onlyOwner {
        collateralSellList.push(_newColl);
    }

    function removeFromCollateralSellList(uint256 _removeIndex) external _onlyOwner {
        collateralSellList[_removeIndex] = address(0);
    }

    function addToExtraCompoundList(address _newColl) external _onlyOwner {
        extraCollToCompound.push(_newColl);
    }

    function removeFromExtraCompoundList(uint256 _removeIndex) external _onlyOwner {
        extraCollToCompound[_removeIndex] = address(0);
    }

    function changeCaller(address _newCaller) external _onlyOwner {
        caller = _newCaller;
    }

    function transferOwnership(address _newOwner) external _onlyOwner {
        owner = _newOwner;
    }

    function changeRouter(address _newRouter) external _onlyOwner {
        router = IRouter(_newRouter);
    }

}
