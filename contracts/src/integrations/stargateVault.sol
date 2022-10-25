// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "src/Vault.sol";

import {IStargateRouter, IStargateLPStaking} from "src/interfaces/IStargate.sol";

/** 
 * @notice stargateVault is the vault token for stargate LP tokens such as S*USDC and S*USDT. 
 * It collects rewards from the rewardController and distributes them to the
 * swap so that it can autocompound. 
 */

contract stargateVault is Vault {
    // 0 for S*USDC, 1 for S*USDT
    uint256 public PID;

    // 0x8731d54E9D02c286767d56ac03e8037C07e01e98
    IStargateLPStaking stargateLPStaking;
    
    function initialize(
        address _underlying,
        string memory _name,
        string memory _symbol,
        uint256 _adminFee,
        uint256 _callerFee,
        uint256 _maxReinvestStale,
        address _WAVAX,
        address _stargateLPStaking,
        uint256 _PID
    ) public {
        initialize(_underlying,
                    _name,
                    _symbol,
                    _adminFee,
                    _callerFee,
                    _maxReinvestStale,
                    _WAVAX);

        stargateLPStaking = IStargateLPStaking(_stargateLPStaking);
        PID = _PID;
        underlying.approve(_stargateLPStaking, MAX_INT);
    }

    
    function _pullRewards() internal override {
        stargateLPStaking.deposit(PID, 0);
    }


    function receiptPerUnderlying() public override view returns (uint256) {
        if (totalSupply==0) {
            return 10 ** (18 + 18 - underlyingDecimal);
        }
        return (1e18 * totalSupply) / stargateLPStaking.userInfo(PID, address(this)).amount;
    }

    function underlyingPerReceipt() public override view returns (uint256) {
        if (totalSupply==0) {
            return 10 ** underlyingDecimal;
        }
        return (1e18 * stargateLPStaking.userInfo(PID, address(this)).amount) / totalSupply;
    }
    
    function totalHoldings() public override returns (uint256) {
        return stargateLPStaking.userInfo(PID, address(this)).amount;
    }
    
    function _triggerDepositAction(uint256 _amt) internal override {
        stargateLPStaking.deposit(PID, _amt);
    }

    function _triggerWithdrawAction(uint256 amtToReturn) internal override {
        stargateLPStaking.withdraw(PID, amtToReturn);
    }

}
