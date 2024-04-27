// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.15;

import { ISETH } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/tokens/ISETH.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IUniswapSwapRouter, UniswapLiquidityMover } from "../src/LiquidityMover.sol";

import { BaseScript } from "./Base.s.sol";

/// @dev See the Solidity Scripting tutorial: https://book.getfoundry.sh/tutorials/solidity-scripting
contract Deploy is BaseScript {
    function run() public broadcast returns (UniswapLiquidityMover liquidityMover) {
        liquidityMover = new UniswapLiquidityMover(
            // IUniswapSwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564),
            // ISETH(0x96B82B65ACF7072eFEb00502F45757F254c2a0D4)
            IUniswapSwapRouter(0x5615CDAb10dc425a742d643d949a7F474C01abc4),
            ISETH(0x671425Ae1f272Bc6F79beC3ed5C4b00e9c628240),
            IERC20(0x471EcE3750Da237f93B8E339c536989b8978a438)
        );
    }
}
