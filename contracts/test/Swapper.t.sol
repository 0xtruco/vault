// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "ds-test/test.sol";
import "forge-std/console.sol";
import "forge-std/stdlib.sol";
import "forge-std/Vm.sol";
import "./TestERC20.sol";
import "./Utils.sol";
import "src/Swapper.sol";
import {IERC20} from "../src/interfaces/IERC20.sol";

// Run on block 38581442
contract TestSwapper is DSTest {

    Vm public constant vm = Vm(HEVM_ADDRESS);

    Swapper public swapper;
    IERC20 public YETI = IERC20(0x77777777777d4554c39223C354A05825b2E8Faa3); // YETI
    IERC20 public WAVAX = IERC20(0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7); // WAVAX
    uint256 public exchangeRate = 10000000000000000; // 0.01 YETI -> 1 WAVAX. 
    uint256 public lengthActiveSeconds = 86400; // 86400 = one day

    address public YETIHolder = 0x5b7a9DB4d69AD8f5Bb7c443FFc3D35301851157E; // Swaps YETI for WAVAX
    address public YETITreasury = 0xEd287C5cF0b7124c0C0D1dE0db2ff48d61386e61; // Owner of the swapper contract
    address public WAVAXHolder = 0xbf0018390Dca012FabF38Ef8188184d0B18960Ac; // Sends wavax to the swapper contract
    function setUp() public {
        // Deploy swapper contract. 
        vm.startPrank(YETITreasury);
        swapper = new Swapper(address(YETI), address(WAVAX), exchangeRate, lengthActiveSeconds);
        vm.stopPrank();

        // Send WAVAX to the swapper contract 
        vm.startPrank(WAVAXHolder);
        WAVAX.transfer(address(swapper), 1000000000000000000000); // 1000 WAVAX
        vm.stopPrank();

    }

    function testSimpleSwap() public {
        uint swapAmt = 100000000000000000000;
        uint expectedOutputAmt = swapAmt * exchangeRate / 1e18;
        uint balanceBefore = WAVAX.balanceOf(YETIHolder);
        vm.startPrank(YETIHolder);
        // Approve YETI and swap
        YETI.approve(address(swapper), swapAmt);
        swapper.swap(swapAmt);
        vm.stopPrank();
        uint balanceAfter = WAVAX.balanceOf(YETIHolder);
        assertTrue(balanceAfter - balanceBefore == expectedOutputAmt);
        console.log(balanceAfter - balanceBefore);

        // send YETI token out of swap contract.
        uint balanceBeforeTreasury = YETI.balanceOf(YETITreasury);
        vm.startPrank(YETITreasury);
        swapper.sendToken(address(YETI), address(YETITreasury), swapAmt);
        vm.stopPrank();
        uint balanceAfterTreasury = YETI.balanceOf(YETITreasury);
        console.log(balanceAfterTreasury - balanceBeforeTreasury);
        assertTrue(balanceAfterTreasury - balanceBeforeTreasury == swapAmt);

        // Change swap exchange rate
        uint newExchangeRate = 100000000000000000;
        vm.startPrank(YETITreasury);
        swapper.setExchangeRate(newExchangeRate);
        vm.stopPrank();

        swapAmt = 100000000000000000000;
        expectedOutputAmt = swapAmt * newExchangeRate / 1e18;
        balanceBefore = WAVAX.balanceOf(YETIHolder);
        vm.startPrank(YETIHolder);
        // Approve YETI and swap
        YETI.approve(address(swapper), swapAmt);
        swapper.swap(swapAmt);
        vm.stopPrank();
        balanceAfter = WAVAX.balanceOf(YETIHolder);
        assertTrue(balanceAfter - balanceBefore == expectedOutputAmt);
        console.log(balanceAfter - balanceBefore);


        // Test swap duration -- should fail after swap duration
        vm.warp(86401 + block.timestamp);
        vm.startPrank(YETIHolder);
        // Approve YETI and swap
        YETI.approve(address(swapper), swapAmt);
        vm.expectRevert();
        swapper.swap(swapAmt);
        vm.stopPrank();
    }

    function testMaxSwap() public {
        uint swapAmt = 100000000000000000000000;
        uint expectedOutputAmt = swapAmt * exchangeRate / 1e18;
        uint balanceBefore = WAVAX.balanceOf(YETIHolder);
        vm.startPrank(YETIHolder);
        // Approve YETI and swap
        YETI.approve(address(swapper), swapAmt);
        swapper.swap(swapAmt);
        vm.stopPrank();
        uint balanceAfter = WAVAX.balanceOf(YETIHolder);
        assertTrue(balanceAfter - balanceBefore == expectedOutputAmt);
        console.log(balanceAfter - balanceBefore);

        // Swapping for 1 more should fail 
        swapAmt = 1000000000000000000;
        vm.startPrank(YETIHolder);
        // Approve YETI and swap
        YETI.approve(address(swapper), swapAmt);
        vm.expectRevert();
        swapper.swap(swapAmt);
        vm.stopPrank();

        // Another caller should fail to claim from the swap contract not from the owner
        vm.expectRevert();
        swapper.sendToken(address(YETI), address(YETITreasury), swapAmt);
    }

}

