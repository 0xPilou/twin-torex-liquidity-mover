// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {TwinTorexLiquidityMover} from "src/TwinTorexLiquidityMover.sol";
import {ITorex} from "../src/interfaces/superboring/ITorex.sol";
import {MockTorex} from "./mock/MockTorex.sol";
import {LiquidityMoverTestBase} from "./LiquidityMoverTestBase.t.sol";

contract SingleTorexLiquidityMoverTest is LiquidityMoverTestBase {
    TwinTorexLiquidityMover public liquidityMover;
    MockTorex public torex0;
    MockTorex public torex1;

    function setUp() public override {
        super.setUp();
        // Set up testing environment
        liquidityMover = new TwinTorexLiquidityMover();
        torex0 = new MockTorex(_tokenA, _tokenB);
        torex1 = new MockTorex(_tokenB, _tokenA);

        vm.label(address(liquidityMover), "liquidityMover");
        vm.label(address(torex0), "torex0");
        vm.label(address(torex1), "torex1");
    }

    function testMoveLiquidity(bool order) public {
        uint256 _inAmount0 = 500 ether; // 500 A
        uint256 _outMinAmount0 = 1000 ether; // Owe 1000 B

        uint256 _inAmount1 = 500 ether; // 500 B
        uint256 _outMinAmount1 = 250 ether; // Owe 250 A

        uint256 aliceInitialBalance = 5000 ether;

        // Test preconditions
        torex0.setAmounts(_inAmount0, _outMinAmount0);
        torex1.setAmounts(_inAmount1, _outMinAmount1);

        vm.startPrank(treasury);
        _tokenA.transfer(address(torex0), _inAmount0);
        _tokenB.transfer(address(torex1), _inAmount1);

        _tokenA.transfer(address(alice), aliceInitialBalance);
        _tokenB.transfer(address(alice), aliceInitialBalance);
        vm.stopPrank();

        assertEq(_tokenA.balanceOf(alice), aliceInitialBalance);
        assertEq(_tokenB.balanceOf(alice), aliceInitialBalance);
        assertEq(_tokenA.balanceOf(address(torex0)), _inAmount0);
        assertEq(_tokenB.balanceOf(address(torex0)), 0);
        assertEq(_tokenB.balanceOf(address(torex1)), _inAmount1);
        assertEq(_tokenA.balanceOf(address(torex1)), 0);

        assertEq(_tokenA.balanceOf(address(liquidityMover)), 0);
        assertEq(_tokenB.balanceOf(address(liquidityMover)), 0);

        // Call moveLiquidity from the liquiditySource
        vm.startPrank(alice);
        _tokenA.approve(address(liquidityMover), type(uint256).max);
        _tokenB.approve(address(liquidityMover), type(uint256).max);

        if (order) {
            liquidityMover.moveLiquidity(ITorex(address(torex0)), ITorex(address(torex1)));
        } else {
            liquidityMover.moveLiquidity(ITorex(address(torex1)), ITorex(address(torex0)));
        }

        // Test results
        // The torex should have received outToken and sent inToken back to liquiditySource

        uint256 aliceExpectedBalanceTokenA = aliceInitialBalance + 250 ether;
        uint256 aliceExpectedBalanceTokenB = aliceInitialBalance - 500 ether;

        assertEq(_tokenA.balanceOf(alice), aliceExpectedBalanceTokenA, "alice token Balance A after LME");
        assertEq(_tokenB.balanceOf(alice), aliceExpectedBalanceTokenB, "alice token Balance B after LME");

        assertEq(_tokenA.balanceOf(address(torex0)), 0, "Torex0 token A balance after LME");
        assertEq(_tokenB.balanceOf(address(torex0)), _outMinAmount0, "Torex0 token B balance after LME");

        assertEq(_tokenA.balanceOf(address(torex1)), _outMinAmount1, "Torex1 token A balance after LME");
        assertEq(_tokenB.balanceOf(address(torex1)), 0, "Torex1 token B balance after LME");

        assertEq(_tokenA.balanceOf(address(liquidityMover)), 0, "LM Token A alance After LME shall be 0");
        assertEq(_tokenB.balanceOf(address(liquidityMover)), 0, "LM Token B Balance After LME shall be 0");
    }

    function testMoveLiquidity_InvalidInvoker(address _invalidInvoker) public {
        vm.assume(_invalidInvoker != address(0));

        uint256 _inAmount0 = 500 ether; // 500 A
        uint256 _outMinAmount0 = 1000 ether; // Owe 1000 B

        uint256 _inAmount1 = 500 ether; // 500 B
        uint256 _outMinAmount1 = 250 ether; // Owe 250 A

        uint256 aliceInitialBalance = 5000 ether;

        // Test preconditions
        torex0.setAmounts(_inAmount0, _outMinAmount0);
        torex1.setAmounts(_inAmount1, _outMinAmount1);

        vm.startPrank(treasury);
        _tokenA.transfer(address(torex0), _inAmount0);
        _tokenB.transfer(address(torex1), _inAmount1);

        _tokenA.transfer(_invalidInvoker, aliceInitialBalance);
        _tokenB.transfer(_invalidInvoker, aliceInitialBalance);
        vm.stopPrank();

        // Try to call the callback directly, which should fail
        vm.startPrank(_invalidInvoker);
        _tokenB.approve(address(liquidityMover), _outMinAmount0);

        vm.expectRevert(TwinTorexLiquidityMover.INVALID_INVOKER.selector);
        liquidityMover.moveLiquidityCallback(_tokenA, _tokenB, _inAmount0, _outMinAmount0, bytes(""));
        vm.stopPrank();
    }
}
