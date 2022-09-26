// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "src/BareVault.sol";
import "src/interfaces/IGMXRewardRouter.sol";
import "src/interfaces/ICollateralGate.sol";
import "src/interfaces/IYetiGLPMinter.sol";

/** 
 * @notice GLPVault is the vault token for GMX's LP token GLP. It comprises an array of different assets 
 * on Avalanche, at the time of writing including USDC, USDC.e, WBTC.e, BTC.b, WETH.e, and AVAX. 
 * 
 * This vault token doesn't work the same as the other vault tokens, since it will not be permissioned by any
 * other contracts (like borrower operations), and also does not utilize the router underlying contract either. 
 * It does not act as a wrapped token inside the Yeti Finance codebase, and users will enter the vault position
 * first, then deposit it as a bare ERC20 into the protocol. 
 * It inherits BareVault.sol but does not use the rewardToken standard from there. 
 * 
 * To autocompound, we take WAVAX rewards, and send them to a different wallet first, then buy more GLP.
 * 
 * Underlying is a token called fsGLP, which represents the amount of GLP staked in the fee + staking token. 
 * fsGLP is here: 0x9e295B5B976a184B14aD8cd72413aD846C299660
 */

contract GLPVault is BareVault {
    ERC20 public WAVAXToken; 
    IGMXRewardRouter public constant GMXRewardRouter = IGMXRewardRouter(0x82147C5A7E850eA4E28155DF107F2590fD4ba327);

    // There is a mint time limit on GLP. If you mint from an address, you can't send for 15 
    // minutes. This contract will mint the GLP first then handle the time limits. 
    IYetiGLPMinter public yetiGLPMinter;

    // staked GLP contract, used for transfer in and out of GLP which is already staked. 
    ERC20 public constant sGLP = ERC20(0x0b82a1aD2138E9f62454ac41b702B64e0b73d57b);

    ICollateralGate public collateralGate;
    
    function initialize(
        address _underlying,
        string memory _name,
        string memory _symbol,
        uint256 _adminFee,
        uint256 _callerFee,
        uint256 _maxReinvestStale,
        address _WAVAX,
        address _yetiGLPMinter,
        address _collateralGate
    ) public {
        initialize(_underlying,
                    _name,
                    _symbol,
                    _adminFee,
                    _callerFee,
                    _maxReinvestStale,
                    _WAVAX);
        
        WAVAXToken = ERC20(_WAVAX);
        
        yetiGLPMinter = IYetiGLPMinter(_yetiGLPMinter);
        collateralGate = ICollateralGate(_collateralGate);
    }

    /**
     * @notice does special transfer in to this contract using sGLP contract. 
     * Locks a certain amount of YETI into the veYETI contract, in addition
     * to burning a certain amount of veYETI as well. 
     */
    function _triggerDepositAction(uint256 _amt) 
        internal 
        override 
    {
        SafeTransferLib.safeTransferFrom(
            sGLP,
            msg.sender,
            address(this),
            _amt
        );

        // Lock for collateral gating. The user who will be locked is the sender
        // since they are going to receive the tokens. 
        collateralGate.lock(msg.sender, _amt, msg.sender);
    }

    /**
     * @notice does special transfer out from this contract using sGLP contract. 
     * Unlocks a certain amount of YETI from the veYETI contract, which was 
     * locked previously in the contract. 
     */
    function _triggerWithdrawAction(address _to, uint256 _amt)
        internal
        override
    {
        SafeTransferLib.safeTransfer(
            sGLP, 
            _to, 
            _amt
        );

        // Unlock from collateral gating. The user who will be unlocked is the sender
        // regardless of the _to param
        collateralGate.unlock(msg.sender, _amt, msg.sender); // reverts if it failed
    }


    /** 
     * @notice override transfer in order to unlock and lock accordingly
     */
    function transfer(address to, uint256 amount) public override returns (bool) {
        // Do before transfer to meet functionality requirements for in/out trove lock
        collateralGate.unlock(msg.sender, amount, msg.sender);
        collateralGate.lock(to, amount, msg.sender); // reverts if it failed

        balanceOf[msg.sender] -= amount;

        // Cannot overflow because the sum of all user
        // balances can't exceed the max uint256 value.
        unchecked {
            balanceOf[to] += amount;
        }

        emit Transfer(msg.sender, to, amount);

        return true;
    }


    /** 
     * @notice override transferFrom in order to unlock and lock accordingly
     */
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public override returns (bool) {
        uint256 allowed = allowance[from][msg.sender]; // Saves gas for limited approvals.

        if (allowed != type(uint256).max) allowance[from][msg.sender] = allowed - amount;

        // Do before transfer to meet functionality requirements for in/out trove lock
        collateralGate.unlock(from, amount, msg.sender);
        collateralGate.lock(to, amount, msg.sender); // reverts if it failed

        balanceOf[from] -= amount;

        // Cannot overflow because the sum of all user
        // balances can't exceed the max uint256 value.
        unchecked {
            balanceOf[to] += amount;
        }

        emit Transfer(from, to, amount);

        return true;
    }


    // Pulls rewards from GMX router and re-stakes the esGMX rewards, while claiming the WAVAX. 
    function _pullRewards() internal override {
        GMXRewardRouter.handleRewards(true, true, true, true, true, true, false);
    }

    // Special functionality: Sends WAVAX to a different wallet to do the purchase of GLP with 
    // WAVAX, and then that wallet will transfer the GLP into this wallet. After that occurs, 
    // the new underlying per receipt ratio will be correct. 
    function _compound() internal override returns (uint256) {
        if (compounder != address(0) && msg.sender != compounder) {
            return 0;
        }
        lastReinvestTime = block.timestamp;
        // Pull rewards from GMX router. This will auto re-stake esGMX rewards, but claim 
        // all WAVAX rewards.
        uint256 preCompoundUnderlyingValue = _getValueOfUnderlyingPre();
        _pullRewards();
        uint256 WAVAXtoReinvest = WAVAXToken.balanceOf(address(this));

        // Send fees in WAVAX
        uint256 adminAmt = (WAVAXtoReinvest * adminFee) / 10000;
        uint256 callerAmt = (WAVAXtoReinvest * callerFee) / 10000;

        SafeTransferLib.safeTransfer(WAVAXToken, feeRecipient, adminAmt);
        SafeTransferLib.safeTransfer(WAVAXToken, msg.sender, callerAmt);
        emit AdminFeePaid(feeRecipient, adminAmt);
        emit CallerFeePaid(msg.sender, callerAmt);


        // Send to YetiGLPMinter so that it can take the WAVAX and buy more GLP. That 
        // account will have a period where it can't transfer it out, so each reward
        // will lag behind for one compound. If the compound happened less than 15
        // minutes ago, then it will skip this step. 
        WAVAXtoReinvest = WAVAXToken.balanceOf(address(this));
        SafeTransferLib.safeTransfer(WAVAXToken, address(yetiGLPMinter), WAVAXtoReinvest);

        // todo use oracle to see reasonable price here, then set min amount correctly
        yetiGLPMinter.mintGLP(1);
        uint256 postCompoundUnderlyingValue = _getValueOfUnderlyingPost();

        emit Reinvested(
                msg.sender,
                preCompoundUnderlyingValue,
                postCompoundUnderlyingValue
            );
    }
}
