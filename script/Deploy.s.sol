// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.15;

import { IUniswapSwapRouter, UniswapLiquidityMover } from "../src/LiquidityMover.sol";

import { BaseScript } from "./Base.s.sol";

/// @dev See the Solidity Scripting tutorial: https://book.getfoundry.sh/tutorials/solidity-scripting
contract Deploy is BaseScript {
    function run() public broadcast returns (UniswapLiquidityMover liquidityMover) {
        liquidityMover = new UniswapLiquidityMover(IUniswapSwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564));
    }
}
