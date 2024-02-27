// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.15;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IUniswapV3Pool } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import { PRBTest } from "@prb/test/PRBTest.sol";
import { console2 } from "forge-std/console2.sol";
import { StdCheats } from "forge-std/StdCheats.sol";
import { ISETH } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/tokens/ISETH.sol";

import { ILiquidityMover, UniswapLiquidityMover, IUniswapSwapRouter, Torex, Config } from "../src/LiquidityMover.sol";

import { ISuperToken } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperToken.sol";

contract FooTest is PRBTest {
    UniswapLiquidityMover internal sut;

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
            urlOrAlias: "https://opt-mainnet.g.alchemy.com/v2/9fhll0R2q_65eilDZmD4AiUULqr6Ae2a",
            blockNumber: 116_724_050
        });

        Torex torex = Torex(0x2a90d7fdCb5e0506e1799B3ED852A91aC067D36e);

        sut = new UniswapLiquidityMover(
            IUniswapSwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564),
            ISETH(0x4ac8bD1bDaE47beeF2D1c6Aa62229509b962Aa0d) // The n
        );

        // CoreConfig memory torexConfig = torex.getCoreConfig();

        // ISuperToken inToken = torexConfig.inToken;
        // ISuperToken outToken = torexConfig.outToken;
        // emit LogAddress(address(inToken));
        // emit LogAddress(address(outToken));

        // uint256 torexInAmount = inToken.balanceOf(address(torex));
        // assertGt(torexInAmount, 0);
        // emit LogUint256(torexInAmount);

        // uint256 torexMinOutAmount = torex.getBenchmarkQuote(torexInAmount);

        // emit LogUint256(torexMinOutAmount);

        // assertGt(torexMinOutAmount, 0);

        address randomRewardAddress = address(0xa5F402E7B32aBf648C9B0638bb0FAb275AA445b7);
        bool isSuccess = sut.moveLiquidity(torex, randomRewardAddress, 0);

        assertTrue(isSuccess);
        // assertEq(inToken.balanceOf(address(torex)), 0);

        // emit LogUint256(inToken.balanceOf(address(randomRewardAddress)));

        assertTrue(isSuccess);

        // assertGt(inToken.balanceOf(address(randomRewardAddress)), 0);
    }
}
