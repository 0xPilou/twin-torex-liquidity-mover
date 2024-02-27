// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.15;

import { ISETH } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/tokens/ISETH.sol";

import { IUniswapSwapRouter, UniswapLiquidityMover } from "../src/LiquidityMover.sol";

import { BaseScript } from "./Base.s.sol";

/// @dev See the Solidity Scripting tutorial: https://book.getfoundry.sh/tutorials/solidity-scripting
contract Deploy is BaseScript {
    function run() public broadcast returns (UniswapLiquidityMover liquidityMover) {
        liquidityMover = new UniswapLiquidityMover(
            // IUniswapSwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564),
            // ISETH(0x96B82B65ACF7072eFEb00502F45757F254c2a0D4)
            IUniswapSwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564),
            ISETH(0x4ac8bD1bDaE47beeF2D1c6Aa62229509b962Aa0d)
        );
    }
}
