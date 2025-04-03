// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {SingleTorexLiquidityMover} from "src/SingleTorexLiquidityMover.sol";
import {ITorex} from "../src/interfaces/superboring/ITorex.sol";
import {MockTorex} from "./mock/MockTorex.sol";
import {LiquidityMoverTest} from "./LiquidityMoverTest.t.sol";

contract SingleTorexLiquidityMoverTest is LiquidityMoverTest {
    SingleTorexLiquidityMover public liquidityMover;
    MockTorex public torex;

    function setUp() public override {
        super.setUp();
        // Set up testing environment
        liquidityMover = new SingleTorexLiquidityMover();
        torex = new MockTorex(_tokenA, _tokenB);
    }

    function testMoveLiquidity(uint256 _inAmount, uint256 _minOutAmount) public {
        _inAmount = bound(_inAmount, 1, 1_000_000 ether);
        _minOutAmount = bound(_minOutAmount, 1, 1_000_000 ether);

        // Test preconditions
        torex.setAmounts(_inAmount, _minOutAmount);
        vm.startPrank(treasury);
        _tokenA.transfer(address(torex), _inAmount);
        _tokenB.transfer(address(alice), _minOutAmount);
        vm.stopPrank();

        assertEq(_tokenA.balanceOf(alice), 0);
        assertEq(_tokenB.balanceOf(alice), _minOutAmount);
        assertEq(_tokenA.balanceOf(address(torex)), _inAmount);
        assertEq(_tokenB.balanceOf(address(torex)), 0);

        assertEq(_tokenA.balanceOf(address(liquidityMover)), 0);
        assertEq(_tokenB.balanceOf(address(liquidityMover)), 0);

        // Call moveLiquidity from the liquiditySource
        vm.startPrank(alice);
        _tokenB.approve(address(liquidityMover), _minOutAmount);
        liquidityMover.moveLiquidity(ITorex(address(torex)));

        // Test results
        // The torex should have received outToken and sent inToken back to liquiditySource
        assertEq(_tokenA.balanceOf(alice), _inAmount);
        assertEq(_tokenB.balanceOf(alice), 0);
        assertEq(_tokenA.balanceOf(address(torex)), 0);
        assertEq(_tokenB.balanceOf(address(torex)), _minOutAmount);

        assertEq(_tokenB.balanceOf(address(liquidityMover)), 0);
        assertEq(_tokenA.balanceOf(address(liquidityMover)), 0);
    }

    function testMoveLiquidity_InvalidInvoker(address _invalidInvoker, uint256 _inAmount, uint256 _minOutAmount)
        public
    {
        vm.assume(_invalidInvoker != address(0));
        _inAmount = bound(_inAmount, 1, 1_000_000 ether);
        _minOutAmount = bound(_minOutAmount, 1, 1_000_000 ether);

        // Test preconditions
        torex.setAmounts(_inAmount, _minOutAmount);
        vm.startPrank(treasury);
        _tokenA.transfer(address(torex), _inAmount);
        _tokenB.transfer(address(_invalidInvoker), _minOutAmount);
        vm.stopPrank();

        // Try to call the callback directly, which should fail
        vm.startPrank(_invalidInvoker);
        _tokenB.approve(address(liquidityMover), _minOutAmount);

        vm.expectRevert(SingleTorexLiquidityMover.INVALID_INVOKER.selector);
        liquidityMover.moveLiquidityCallback(_tokenA, _tokenB, _inAmount, _minOutAmount, bytes(""));
        vm.stopPrank();
    }
}
