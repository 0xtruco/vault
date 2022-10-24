// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import {IERC20} from "./interfaces/IERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";


interface IYetiController {
    function getValidCollateral() external view returns (address[] memory);
    function isWrappedMany(address[] memory _collaterals) external view returns (bool[] memory wrapped);
}

interface IYetiVault {
    function compound() external returns (uint256);
    function underlying() external returns (address);
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
    using SafeTransferLib for IERC20;

    IYetiController constant public yetiController = IYetiController(0xcCCCcCccCCCc053fD8D1fF275Da4183c2954dBe3);

    address constant public yusd = 0x111111111111ed1D73f860F57b2798b683f2d325;

    address public owner;

    address public caller;

    IRouter public router;

    // If they are not wrapped in YetiController but need to compound, add to this list
    address[] public extraCollToCompound;

    address[] public collateralSellList;

    event YUSDGained(uint256 yusdGained);

    event TokenTransferredOut(address _token, uint256 _amount, address _recipient);

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
                address underlying = IYetiVault(validCollateral[i]).underlying();
                collateralSellList.push(underlying);
            }
        }
    }

    // Calls compound on valid wrapped collateral + any extra
    // Goes from i_1 to j_1 in first list from whitelisted collateral, and from i_2 to j_2 in second list from extra coll compound list.
    function callCompound(uint256 _startIndexValidCollateral, uint256 _endIndexValidCollateral, uint256 _startIndexExtraCompound, uint256 _endIndexExtraCompound) external _onlyCaller {
        address[] memory validCollateral = yetiController.getValidCollateral();
        bool[] memory wrapped = yetiController.isWrappedMany(validCollateral);
        _endIndexValidCollateral = _min(_endIndexValidCollateral, collateralSellList.length);
        _endIndexExtraCompound = _min(_endIndexExtraCompound, extraCollToCompound.length);
        for (uint i = _startIndexValidCollateral; i < _endIndexValidCollateral; ++i) {
            if (wrapped[i]) {
                IYetiVault(validCollateral[i]).compound();
            }
        }
        for (uint i = _startIndexExtraCompound; i < _endIndexExtraCompound; ++i) {
            IYetiVault(extraCollToCompound[i]).compound();
        }
    }

    // Calls compound on the input list
    // Assumes all are wrapped and can compound. 
    function callCompoundColls(address[] calldata _colls) external _onlyCaller {
        for (uint i; i < _colls.length; ++i) {
            IYetiVault(_colls[i]).compound();
        }
    }

    // Transfers out ERC20 to the recipient, onlyOwner
    function transferERC20(address _token, uint256 _amount, address _recipient) external _onlyOwner {
        SafeTransferLib.safeTransfer(ERC20(_token), _recipient, _amount);
        emit TokenTransferredOut(_token, _amount, _recipient);
    }

    // ========= External functions for selling through router, onlyOwner, for the balances of the compounder =========


    // Sell from start to end in the collateral sell list. 
    // Assumes route exists for all indices
    function sellThroughRouter(uint256 _startIndex, uint256 _endIndex) external _onlyOwner returns (uint256 yusdGained) {
        _endIndex = _min(_endIndex, collateralSellList.length);
        for (uint i = _startIndex; i < _endIndex; ++i) {
            address collateral = collateralSellList[i];
            uint256 balance = IERC20(collateral).balanceOf(address(this));
            SafeTransferLib.safeApprove(ERC20(collateral), address(router), balance);
            yusdGained += router.fullTx(collateral, yusd, balance, 1);
        }
        emit YUSDGained(yusdGained);
    }

    // Sell for the list of collateral sent in as input
    function sellThroughRouterColls(address[] calldata _colls) external _onlyOwner returns (uint256 yusdGained) {
        for (uint i; i < _colls.length; ++i) {
            address collateral = _colls[i];
            uint256 balance = IERC20(collateral).balanceOf(address(this));
            SafeTransferLib.safeApprove(ERC20(collateral), address(router), balance);
            yusdGained += router.fullTx(collateral, yusd, balance, 1);
        }
        emit YUSDGained(yusdGained);
    }

    // ========= External functions for selling through router =========

    // Sells for someone else through the router, compounds YUSD to this address
    // Transfers the YUSD back out once it is done, to the sender.
    function sellThroughRouterForSender(uint256 _startIndex, uint256 _endIndex) external returns (uint256 yusdGained) {
        _endIndex = _min(_endIndex, collateralSellList.length);
        for (uint i = _startIndex; i < _endIndex; ++i) {
            address collateral = collateralSellList[i];
            uint256 balance = IERC20(collateral).balanceOf(msg.sender);
            SafeTransferLib.safeTransferFrom(ERC20(collateral), msg.sender, address(this), balance);
            SafeTransferLib.safeApprove(ERC20(collateral), address(router), balance);
            yusdGained += router.fullTx(collateral, yusd, balance, 1);
        }
        SafeTransferLib.safeTransfer(ERC20(yusd), msg.sender, yusdGained);
        emit TokenTransferredOut(yusd, yusdGained, msg.sender);
    }

    // Sells for someone else through the router, compounds YUSD to this address
    // Transfers the YUSD back out once it is done, to the sender.
    function sellThroughRouterForSenderColls(address[] calldata _colls) external returns (uint256 yusdGained) {
        for (uint i; i < _colls.length; ++i) {
            address collateral = _colls[i];
            uint256 balance = IERC20(collateral).balanceOf(msg.sender);
            SafeTransferLib.safeTransferFrom(ERC20(collateral), msg.sender, address(this), balance);
            SafeTransferLib.safeApprove(ERC20(collateral), address(router), balance);
            yusdGained += router.fullTx(collateral, yusd, balance, 1);
        }
        SafeTransferLib.safeTransfer(ERC20(yusd), msg.sender, yusdGained);
        emit TokenTransferredOut(yusd, yusdGained, msg.sender);
    }

    function addToCollateralSellList(address _newColl) external _onlyOwner {
        collateralSellList.push(_newColl);
    }

    function removeFromCollateralSellList(uint256 _removeIndex) external _onlyOwner {
        require(_removeIndex < collateralSellList.length, "Index out of bounds");
        collateralSellList[_removeIndex] = collateralSellList[collateralSellList.length - 1];
        collateralSellList.pop();
    }

    function addToExtraCompoundList(address _newColl) external _onlyOwner {
        extraCollToCompound.push(_newColl);
    }

    function removeFromExtraCompoundList(uint256 _removeIndex) external _onlyOwner {
        require(_removeIndex < extraCollToCompound.length, "Index out of bounds");
        extraCollToCompound[_removeIndex] = extraCollToCompound[extraCollToCompound.length - 1];
        collateralSellList.pop();
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

    function _min(uint256 _a, uint256 _b) internal pure returns (uint256) {
        if (_a > _b) {
            return _b;
        }
        return _a;
    }
}
