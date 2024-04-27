// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.15;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IUniswapV3Pool } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import { PRBTest } from "@prb/test/PRBTest.sol";
import { console2 } from "forge-std/console2.sol";
import { StdCheats } from "forge-std/StdCheats.sol";
import { ISETH } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/tokens/ISETH.sol";
import { IWETH9 } from "@uniswap/v3-periphery/contracts/interfaces/external/IWETH9.sol";

import { ILiquidityMover, UniswapLiquidityMover, IUniswapSwapRouter, Torex, Config } from "../src/LiquidityMover.sol";

import { ISuperToken } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperToken.sol";

contract LiquidityMoverTests is PRBTest {
    UniswapLiquidityMover internal sut;

    IERC20 internal constant OPx = IERC20(0x1828Bff08BD244F7990edDCd9B19cc654b33cDB4);
    IERC20 internal constant OP = IERC20(0x4200000000000000000000000000000000000042);

    IERC20 internal constant USDCx = IERC20(0x8430F084B939208E2eDEd1584889C9A66B90562f);
    IERC20 internal constant USDC = IERC20(0x7F5c764cBc14f9669B88837ca1490cCa17c31607);

    function setUp() public {
        // Otherwise, run the test against the mainnet fork.
        // todo: env variable
        vm.createSelectFork({
            urlOrAlias: "https://opt-mainnet.g.alchemy.com/v2/9fhll0R2q_65eilDZmD4AiUULqr6Ae2a",
            blockNumber: 116_756_644
        });

        sut = new UniswapLiquidityMover(
            IUniswapSwapRouter(0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45), // "SwapRouter02"! (not just "SwapRouter")
            ISETH(0x4ac8bD1bDaE47beeF2D1c6Aa62229509b962Aa0d), // The Super Token on for Native Asset on Optimism
            IERC20(address(0))
        );
    }

    function test_ETHx_to_OPx() external {
        Torex torex = Torex(0x605a2903C819CFA41ea6dD38AE2D1aAF6d01Ec33);
        _testTorex(torex, address(sut.WETH())); // (ETHx -> OPx)
    }

    function test_OPx_to_ETHx() external {
        _testTorex(Torex(0x4eA8d965e3337AFd4614d2D42ED3310AD7d0B550), address(OP)); // (OPx -> ETHx)
    }

    function test_OPx_to_USDCx() external {
        _testTorex(Torex(0x2a90d7fdCb5e0506e1799B3ED852A91aC067D36e), address(OP)); // (OPx -> USDCx)
    }

    function test_USDCx_to_OPx() external {
        _testTorex(Torex(0x82D28B941dB301Ea7F32d4389BBB98b1A3eA3235), address(USDC)); // (USDCx -> OPx)
    }

    function _testTorex(Torex torex, address rewardToken) internal {
        assertTrue(sut.moveLiquidity(torex));

        ISuperToken outToken = torex.getConfig().outToken;
        assertEq(outToken.balanceOf(address(sut)), 0);
        address outTokenUnderlying = outToken.getUnderlyingToken();
        if (outTokenUnderlying != address(0)) {
            assertLte(IERC20(outTokenUnderlying).balanceOf(address(sut)), 0);
        }

        assertEq(IERC20(rewardToken).balanceOf(address(sut)), 0);
        assertEq(IERC20(rewardToken).balanceOf(address(torex)), 0);

        ISuperToken inToken = torex.getConfig().inToken;

        address inTokenUnderlying = inToken.getUnderlyingToken();
        uint8 inTokenDecimals = inToken.getUnderlyingDecimals();
        if (inTokenDecimals < 18) {
            assertLte(inToken.balanceOf(address(sut)), 1_000_000_000_000);
        } else {
            assertLte(inToken.balanceOf(address(sut)), 0);
        }

        if (inTokenUnderlying != address(0)) {
            assertEq(IERC20(inTokenUnderlying).balanceOf(address(sut)), 0);
        }
        assertEq(address(sut).balance, 0);
    }
}
