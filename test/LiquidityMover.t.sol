// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.15;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IUniswapV3Pool } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import { PRBTest } from "@prb/test/PRBTest.sol";
import { console2 } from "forge-std/console2.sol";
import { StdCheats } from "forge-std/StdCheats.sol";
import { ISETH } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/tokens/ISETH.sol";

import {
    ILiquidityMover, UniswapLiquidityMover, IUniswapSwapRouter, Torex, CoreConfig
} from "../src/LiquidityMover.sol";

import { ISuperToken } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperToken.sol";

contract FooTest is PRBTest {
    UniswapLiquidityMover internal sut;

    uint128 private constant ONE_IN_Q32_96 = 1 << 96;

    function setUp() public virtual {
        // sut = new UniswapLiquidityMover(
        //     IUniswapSwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564),
        //     ISETH(0x96B82B65ACF7072eFEb00502F45757F254c2a0D4)
        // );
    }

    function testFork_Example() external {
        string memory alchemyApiKey = vm.envOr("API_KEY_POLYGONSCAN", string(""));
        if (bytes(alchemyApiKey).length == 0) {
            return;
        }

        // Otherwise, run the test against the mainnet fork.
        vm.createSelectFork({
            urlOrAlias: "https://polygon-mumbai.g.alchemy.com/v2/Ra72TykU9ohKJ99Np3E7T-n-crUM1cuU",
            blockNumber: 45_149_005
        });

        Torex torex = Torex(0xA18cDB16562d9ebB5dB2dc599c14a9A1062b6DB9);
        CoreConfig memory torexConfig = torex.getCoreConfig();

        IUniswapV3Pool uniV3Pool = torexConfig.uniV3Pool;
        emit LogAddress(address(uniV3Pool));

        sut = new UniswapLiquidityMover(
            IUniswapSwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564),
            ISETH(0x96B82B65ACF7072eFEb00502F45757F254c2a0D4)
        );

        ISuperToken inToken = torexConfig.inToken;
        ISuperToken outToken = torexConfig.outToken;
        emit LogAddress(address(inToken));
        emit LogAddress(address(outToken));

        uint256 torexInAmount = inToken.balanceOf(address(torex));
        assertGt(torexInAmount, 0);
        emit LogUint256(torexInAmount);

        uint256 torexMinOutAmount = torex.getBenchmarkQuote(torexInAmount);

        emit LogUint256(torexMinOutAmount);

        assertGt(torexMinOutAmount, 0);

        bool isSuccess = sut.moveLiquidity(torex, address(0), 0, 1);

        assertTrue(isSuccess);
    }
}
