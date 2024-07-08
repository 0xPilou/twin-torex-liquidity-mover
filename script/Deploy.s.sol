// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.15;

import { ISETH } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/tokens/ISETH.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IUniswapSwapRouter, NonprofitUniswapLiquidityMover as UniswapLiquidityMover } from "../src/LiquidityMover.sol";

import { BaseScript } from "./Base.s.sol";

/// @dev See the Solidity Scripting tutorial: https://book.getfoundry.sh/tutorials/solidity-scripting
contract Deploy is BaseScript {
    function run() public broadcast returns (UniswapLiquidityMover liquidityMover) {
        liquidityMover = new UniswapLiquidityMover(
            // IUniswapSwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564),
            // ISETH(0x96B82B65ACF7072eFEb00502F45757F254c2a0D4)
            IUniswapSwapRouter(0x2626664c2603336E57B271c5C0b26F421741e481),
            ISETH(0x46fd5cfB4c12D87acD3a13e92BAa53240C661D93),
            IERC20(address(0))
        );
    }
}
