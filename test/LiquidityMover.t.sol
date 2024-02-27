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

contract LiquidityMoverTests is PRBTest {
    UniswapLiquidityMover internal sut;

    function setUp() public {
        string memory alchemyApiKey = vm.envOr("API_KEY_POLYGONSCAN", string(""));
        if (bytes(alchemyApiKey).length == 0) {
            return;
        }

        // Otherwise, run the test against the mainnet fork.
        vm.createSelectFork({
            urlOrAlias: "https://opt-mainnet.g.alchemy.com/v2/9fhll0R2q_65eilDZmD4AiUULqr6Ae2a",
            blockNumber: 116_724_051
        });

        sut = new UniswapLiquidityMover(
            IUniswapSwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564),
            ISETH(0x4ac8bD1bDaE47beeF2D1c6Aa62229509b962Aa0d) // The n
        );
    }

    function test_ETHx_OPx() external {
        _testTorex(Torex(0x605a2903C819CFA41ea6dD38AE2D1aAF6d01Ec33)); // (ETHx -> OPx)
    }

    function test_OPx_ETHx() external {
        _testTorex(Torex(0x4eA8d965e3337AFd4614d2D42ED3310AD7d0B550)); // (OPx -> ETHx)
    }

    function test_OPx_USDCx() external {
        _testTorex(Torex(0x2a90d7fdCb5e0506e1799B3ED852A91aC067D36e)); // (OPx -> USDCx)
    }

    function test_USDCx_OPx() external {
        _testTorex(Torex(0x82D28B941dB301Ea7F32d4389BBB98b1A3eA3235)); // (USDCx -> OPx)
    }

    function _testTorex(Torex torex) internal {
        address randomRewardAddress = address(0xa5F402E7B32aBf648C9B0638bb0FAb275AA445b7);
        bool isSuccess = sut.moveLiquidity(torex, randomRewardAddress, 0);

        assertTrue(isSuccess);
    }
}
