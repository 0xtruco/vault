// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "ds-test/test.sol";
import "forge-std/console.sol";
import "forge-std/stdlib.sol";
import "forge-std/Vm.sol";
import "src/integrations/stargateVault.sol";
import "./TestERC20.sol";
import "./Utils.sol";


// This test covers integration for comp-like vaults

contract TestStargateVault is DSTest {

    uint constant ADMINFEE=100;
    uint constant CALLERFEE=10;
    uint constant MAX_REINVEST_STALE= 1 hours;
    uint constant MAX_INT= 2**256 - 1;
    Vm public constant vm = Vm(HEVM_ADDRESS);

    IERC20 constant USDC = IERC20(0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E); //USDC
    address constant usdcHolder = 0x279f8940ca2a44C35ca3eDf7d28945254d0F0aE6;
    IERC20 constant WAVAX = IERC20(0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7); //WAVAX
    address constant wavaxHolder = 0xBBff2A8ec8D702E61faAcCF7cf705968BB6a5baB; 

    IERC20 constant JLP = IERC20(0xA389f9430876455C36478DeEa9769B7Ca4E3DDB1); //USDC
    address constant JLPHolder = 0x8361dde63F80A24256657D19a5B659F2FB9df2aB;

    IERC20 constant QI = IERC20(0x8729438EB15e2C8B576fCc6AeCdA6A148776C0F5); //USDC
    address constant QIWAVAX = 0xE530dC2095Ef5653205CF5ea79F8979a7028065c;


    // address constant joePair = 0xA389f9430876455C36478DeEa9769B7Ca4E3DDB1; // USDC-WAVAX
    address constant joeRouter = 0x60aE616a2155Ee3d9A68541Ba4544862310933d4;
    // address constant aave = 0x4F01AeD16D97E3aB5ab2B501154DC9bb0F1A5A2C;
    // address constant aaveV3 = 0x794a61358D6845594F94dc1DB02A252b5b4814aD;

    address constant stargateRouter = 0x45A01E4e04F14f7A4a6702c74187c5F6222033cd;
    address constant stargateLPStaking = 0x8731d54E9D02c286767d56ac03e8037C07e01e98;

    IERC20 constant S_USDC = IERC20(0x1205f31718499dBf1fCa446663B532Ef87481fe1);
    address constant S_USDCHolder = 0x444e01DCb3A1eC1b1aa1344505ed7C8690D53281;

    address constant STG = 0x2F6F07CDcf3588944Bf4C42aC74ff24bF56e7590;
    address constant STGHolder = 0x4aeFa39caEAdD662aE31ab0CE7c8C2c9c0a013E8;
    
    stargateVault public vault;
    uint public underlyingBalance;
    function setUp() public {
        vault = new stargateVault();
        vault.initialize(
            address(S_USDC),
            "Vault",
            "VAULT",
            ADMINFEE,
            CALLERFEE,
            MAX_REINVEST_STALE,
            address(WAVAX),
            stargateLPStaking,
            0);
        
        vault.setStargateRouter(stargateRouter);

        vault.setJoeRouter(joeRouter);
        vault.setApprovals(address(WAVAX), joeRouter, MAX_INT);
        vault.setApprovals(address(USDC), joeRouter, MAX_INT);
        vault.setApprovals(address(STG), joeRouter, MAX_INT);

        vault.setApprovals(address(S_USDC), stargateLPStaking, MAX_INT);
        vault.setApprovals(address(USDC), stargateRouter, MAX_INT);

        // address JOEWAVAX = 0x454E67025631C065d3cFAD6d71E6892f74487a15;
        address STGUSDC = 0x330f77BdA60D8daB14d2bb4F6248251443722009;
        Router.Node[] memory _path = new Router.Node[](2);
        _path[0] = Router.Node(STGUSDC, 1, STG, address(USDC), 0, 0, 0);
        // _path[1] = Router.Node(WAVAXUSDC, 1, address(WAVAX), address(USDC), 0, 0, 0);
        _path[1] = Router.Node(address(S_USDC), 10, address(USDC), address(S_USDC), 1, 0, 0);
        vault.setRoute(STG, address(S_USDC), _path);

        // Router.Node[] memory _path2 = new Router.Node[](3);
        // _path2[0] = Router.Node(QIWAVAX, 1, address(QI), address(WAVAX), 0, 0, 0);
        // _path2[1] = Router.Node(joePair, 1, address(WAVAX), address(USDC), 0, 0, 0);
        // _path2[2] = Router.Node(address(qUSDC), 7, address(USDC), address(qUSDC), 0, 0, 0);
        // vault.setRoute(address(QI), address(qUSDC), _path2);

        vm.startPrank(wavaxHolder);
        WAVAX.transfer(address(this), WAVAX.balanceOf(wavaxHolder));
        vm.stopPrank();
        vm.startPrank(usdcHolder);
        USDC.transfer(address(this), USDC.balanceOf(usdcHolder));
        vm.stopPrank();
        vm.startPrank(S_USDCHolder);
        S_USDC.transfer(address(this), S_USDC.balanceOf(S_USDCHolder));
        vm.stopPrank();
        

        vault.pushRewardToken(STG);

        S_USDC.approve(address(vault), MAX_INT);
        underlyingBalance=S_USDC.balanceOf(address(this));
        // vm.warp(21495230+20 days);
    }


    function testVanillaDeposit(uint96 amt) public returns (uint) {
        // uint amt = 1e10;
        vm.assume(amt < 100000e6);
        vm.assume(amt > 1e6);
        // if (amt > underlyingBalance || amt<vault.MIN_FIRST_MINT()) {
        //     return 0;
        // }
        uint preBalance = vault.balanceOf(address(this));
        vault.deposit(amt);
        uint postBalance = vault.balanceOf(address(this));
        assertTrue(postBalance == preBalance + amt * 1e12 - vault.FIRST_DONATION());
        return amt;
    }

    function testViewFuncs1(uint96 amt) public {
        vm.assume(amt < 100000e6);
        vm.assume(amt > 1e6);
        // if (amt > underlyingBalance || amt<vault.MIN_FIRST_MINT()) {
        //     return;
        // }
        assertTrue(vault.receiptPerUnderlying() == 1e30);
        assertTrue(vault.underlyingPerReceipt() == 1e6);
        assertTrue(vault.totalSupply() == 0);
        vault.deposit(amt);
        assertTrue(vault.totalSupply() == amt * 1e12, "Hello");
        assertTrue(vault.receiptPerUnderlying() == 1e30);
        assertTrue(vault.underlyingPerReceipt() == 1e6);
        console.log("We back");
    }


    function testVanillaDepositNredeem(uint96 amt) public {
        vm.assume(amt < 100000e6);
        vm.assume(amt > 1e6);
        // if (amt > underlyingBalance || amt<vault.MIN_FIRST_MINT()) {
        //     return;
        // }
        vault.deposit(amt);
        uint preBalanceVault = vault.balanceOf(address(this));
        uint preBalanceToken = S_USDC.balanceOf(address(this));
        vault.redeem(preBalanceVault);
        uint postBalanceVault = vault.balanceOf(address(this));
        uint postBalanceToken = S_USDC.balanceOf(address(this));
        console.log(postBalanceVault, preBalanceVault);
        console.log(postBalanceToken, preBalanceToken);
        console.log("Amt", amt);
        assertTrue(postBalanceVault == preBalanceVault - (amt * 1e12 - vault.FIRST_DONATION()));
        assertTrue(postBalanceToken == preBalanceToken + ((amt * 1e12 - vault.FIRST_DONATION())/1e12));
    }
    function testVanillaDepositNCompound(uint96 amt) public returns (uint) {
        vm.assume(amt < 100000e6);
        vm.assume(amt > 1e6);
        // uint amt = 1e18;
        // if (amt > underlyingBalance || amt<vault.MIN_FIRST_MINT()) {
        //     return 0;
        // }
        vault.deposit(amt);
        uint preBalance = vault.underlyingPerReceipt();
        vm.warp(block.timestamp+100 days);
        vm.startPrank(STGHolder);
        IERC20(STG).transfer(address(vault), 10e18);
        vm.stopPrank();
        vault.compound();
        uint postBalance = vault.underlyingPerReceipt();
        console.log(preBalance, postBalance);
        assertTrue(postBalance > preBalance);
        return amt;
    }
    function testVanillaDepositNCompoundredeem(uint96 amt) public returns (uint) {
        vm.assume(amt < 100000e6);
        vm.assume(amt > 1e8);
        // // uint amt = 1e18;
        // if (amt > underlyingBalance || amt<vault.MIN_FIRST_MINT()) {
        //     return 0;
        // }
        vault.deposit(amt);
        uint preBalance = vault.underlyingPerReceipt();
        vm.warp(block.timestamp+100 days);
        console.log(vault.totalHoldings());
        vm.startPrank(STGHolder);
        IERC20(STG).transfer(address(vault), 10e18);
        vm.stopPrank();
        vault.compound();
        console.log(vault.totalHoldings());
        uint postBalance = vault.underlyingPerReceipt();
        console.log(preBalance, postBalance);
        vault.redeem(vault.balanceOf(address(this)));
        assertTrue(amt < S_USDC.balanceOf(address(this)));
        return amt;
    }
}
