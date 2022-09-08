// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "ds-test/test.sol";
import "forge-std/console.sol";
import "forge-std/stdlib.sol";
import "forge-std/Vm.sol";
import "./TestERC20.sol";
import "./Utils.sol";

import "src/integrations/GLPVault.sol";
import "src/integrations/YetiGLPMinter.sol";
import "./TestCollateralGate.sol";

// This test covers integration for the GLP vault

contract TestGLPVault is DSTest {

    uint constant ADMINFEE=100;
    uint constant CALLERFEE=10;
    uint constant MAX_REINVEST_STALE = 1 hours;
    uint constant MAX_INT= 2**256 - 1;
    Vm public constant vm = Vm(HEVM_ADDRESS);

    IERC20 constant WAVAX = IERC20(0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7); //WAVAX
    address constant wavaxHolder = 0xBBff2A8ec8D702E61faAcCF7cf705968BB6a5baB; 
    
    GLPVault public vault;
    YetiGLPMinter public minter;
    uint public underlyingBalance;
    address public collateralGate;

    IERC20 constant fsGLP = IERC20(0x9e295B5B976a184B14aD8cd72413aD846C299660);
    address public GMXRewardRouter = 0x82147C5A7E850eA4E28155DF107F2590fD4ba327;
    IERC20 public constant sGLP = IERC20(0x0b82a1aD2138E9f62454ac41b702B64e0b73d57b);

    // Staked GMX
    IERC20 public constant sbfGMX = IERC20(0x4d268a7d4C16ceB5a606c173Bd974984343fea13);

    address constant fsGLPHolder = 0xFB505Aa37508B641CE4D8f066867Db3B3F66185D;


    function setUp() public {
        vault = new GLPVault();
        minter = new YetiGLPMinter();
        collateralGate = address(new TestCollateralGate());
        vault.initialize(
            address(fsGLP),
            "GLP Vault",
            "G.V",
            ADMINFEE,
            CALLERFEE,
            MAX_REINVEST_STALE,
            address(WAVAX),
            address(minter),
            collateralGate);
        
        vault.setFeeRecipient(address(1));

        minter.initialize(
            address(vault)
        );

        vm.startPrank(wavaxHolder);
        WAVAX.transfer(address(this), WAVAX.balanceOf(wavaxHolder));
        vm.stopPrank();

        vm.startPrank(fsGLPHolder);
        sGLP.transfer(address(this), 10000e18);
        vm.stopPrank();
        underlyingBalance = fsGLP.balanceOf(address(this));
    }

    function testVanillaDeposit(uint96 amt) public returns (uint) {
        if (amt > underlyingBalance || amt<vault.MIN_FIRST_MINT()) {
            return 0;
        }
        sGLP.approve(address(vault), amt);
        uint preBalanceToken = vault.balanceOf(address(this));
        vault.deposit(amt);
        uint postBalanceToken = vault.balanceOf(address(this));
        assertTrue(postBalanceToken == preBalanceToken + amt - vault.FIRST_DONATION());
        return amt;
    }

    function testViewFuncs1(uint96 amt) public {
        if (amt > underlyingBalance || amt<vault.MIN_FIRST_MINT()) {
            return;
        }
        assertTrue(vault.receiptPerUnderlying() == 1e18);
        assertTrue(vault.underlyingPerReceipt() == 1e18);
        assertTrue(vault.totalSupply() == 0);
        sGLP.approve(address(vault), amt);
        vault.deposit(amt);
        assertTrue(vault.totalSupply() == amt);
        assertTrue(vault.receiptPerUnderlying() == 1e18);
        assertTrue(vault.underlyingPerReceipt() == 1e18);
    }


    function testVanillaDepositNredeem(uint96 amt) public {
        if (amt > underlyingBalance || amt<vault.MIN_FIRST_MINT()) {
            return;
        }
        sGLP.approve(address(vault), amt);
        vault.deposit(amt);
        uint preBalanceVault = vault.balanceOf(address(this));
        uint preBalanceToken = fsGLP.balanceOf(address(this));
        vault.redeem(preBalanceVault);
        uint postBalanceVault = vault.balanceOf(address(this));
        uint postBalanceToken = fsGLP.balanceOf(address(this));
        console.log(postBalanceVault, preBalanceVault);
        console.log(postBalanceToken, preBalanceToken);
        assertTrue(postBalanceVault == preBalanceVault - (amt - vault.FIRST_DONATION()));
        assertTrue(postBalanceToken == preBalanceToken + (amt - vault.FIRST_DONATION()));
    }

    function testVanillaDepositNCompoundOnly(uint96 amt) public returns (uint) {
        // uint amt = 1e18;
        if (amt > underlyingBalance || amt<1e5*vault.MIN_FIRST_MINT()) {
            return 0;
        }
        sGLP.approve(address(vault), amt);
        vault.deposit(amt);
        uint preBalance = vault.underlyingPerReceipt();
        uint preBalancesbfGMX = sbfGMX.balanceOf(address(vault));
        uint preBalanceWAVAX = WAVAX.balanceOf(address(this));
        uint preBalanceWAVAXFeeRecipient = WAVAX.balanceOf(address(this));
        vm.warp(block.timestamp + 100 days);
        vault.compound();
        // Wait 15 mintues for mint amount to enter
        vm.warp(block.timestamp + 15 minutes);
        vault.compound();
        uint postBalance = vault.underlyingPerReceipt();
        uint postBalancesbfGMX = sbfGMX.balanceOf(address(vault));
        uint postBalanceWAVAX = WAVAX.balanceOf(address(this));
        uint postBalanceWAVAXFeeRecipient = WAVAX.balanceOf(address(this));
        assertTrue(postBalance > preBalance, "Balances did not increase");
        assertTrue(postBalancesbfGMX > preBalancesbfGMX, "esGMX Not staked");
        assertTrue(postBalanceWAVAX > preBalanceWAVAX, "WAVAX Rewards not sent to caller");
        assertTrue(postBalanceWAVAXFeeRecipient > preBalanceWAVAXFeeRecipient, "WAVAX Rewards not sent to caller");
        return amt;
    }

    function testVanillaDepositNCompoundredeem(uint96 amt) public returns (uint) {
        // uint amt = 1e18;
        if (amt > underlyingBalance || amt<vault.MIN_FIRST_MINT()) {
            return 0;
        }
        sGLP.approve(address(vault), amt);
        vault.deposit(amt);
        vm.warp(block.timestamp + 100 days);
        vault.compound();
        // Wait 15 mintues for mint amount to enter
        vm.warp(block.timestamp + 15 minutes);
        vault.compound();
        vault.redeem(vault.balanceOf(address(this)));
        assertTrue(amt < fsGLP.balanceOf(address(this)), "Balances did not increase");
        return amt;
    }

    function testVanillaDepositNEmergencyRedeem(uint96 amt) public returns (uint) {
        if (amt > underlyingBalance || amt<vault.MIN_FIRST_MINT()) {
            return 0;
        }
        sGLP.approve(address(vault), amt);
        vault.deposit(amt);
        vm.warp(block.timestamp + 100 days);

        vault.emergencyRedeem(amt/2);
        assertTrue(vault.lastReinvestTime() < block.timestamp, "Should not have compounded");
    }

    // The GLP contract can only mint once every 15 minutes for our minter address. 
    // If it mints once, then another mint is called, it should not increase until 15 
    // minutes from the original mint, but shouldn't revert. 
    function testCompoundWindow(uint96 amt) public returns (uint) {
        if (amt > underlyingBalance || amt<1e5*vault.MIN_FIRST_MINT()) {
            return 0;
        }
        sGLP.approve(address(vault), amt);
        vault.deposit(amt);
        vm.warp(block.timestamp + 100 days);
        vault.compound();
        uint preBalance = vault.underlyingPerReceipt();
        // Wait 5 minutes twice. Balance should stay the same.
        vm.warp(block.timestamp + 5 minutes);
        vault.compound();
        uint postBalance1 = vault.underlyingPerReceipt();
        vm.warp(block.timestamp + 5 minutes);
        vault.compound();
        uint postBalance2 = vault.underlyingPerReceipt();
        assertTrue(postBalance1 == postBalance2 && postBalance1 == preBalance);
        vm.warp(block.timestamp + 5 minutes);
        vault.compound();
        uint postBalance3 = vault.underlyingPerReceipt();
        assertTrue(postBalance3 > preBalance, "Balances did not increase");
        return amt;
    }
}
