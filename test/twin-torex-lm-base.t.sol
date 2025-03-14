// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.15;

import { PRBTest } from "@prb/test/PRBTest.sol";

import { Torex, TorexConfig } from "../src/ILiquidityMover.sol";
import { console2 } from "forge-std/console2.sol";

import { TwinTorexLiquidityMover } from "../src/TwinTorexLiquidityMover.sol";
import { SwapRouter02LiquidityMover } from "../src/SwapRouter02LiquidityMover.sol";
import { DeployTTLM } from "../script/DeployTTLM.s.sol";
import { Deploy } from "../script/Deploy.s.sol";

import { ISuperToken } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperToken.sol";

contract TTLiquidityMoverTests is PRBTest {
    DeployTTLM deployTTLMScript;
    Deploy deployBLMScript;
    TwinTorexLiquidityMover internal ttlm;
    SwapRouter02LiquidityMover internal blm;

    function _setUpForkAndSut(uint256 blockNumber) private {
        vm.createSelectFork({ urlOrAlias: vm.envString("BASE_RPC"), blockNumber: blockNumber });
        deployTTLMScript = new DeployTTLM();
        deployBLMScript = new Deploy();
        ttlm = deployTTLMScript.run();
        blm = deployBLMScript.run();
    }

    function test_twinTorexLM() external {
        _setUpForkAndSut(27_578_099);
        _testTTLMTorexWithReward(
            Torex(0x267264CFB67B015ea23c97C07d609FbFc06aDC17), Torex(0x269F9EF6868F70fB20DDF7CfDf69Fe1DBFD307dE)
        );
    }

    function test_basicLM() external {
        _setUpForkAndSut(27_578_099);
        _testBLMTorexWithReward(
            Torex(0x267264CFB67B015ea23c97C07d609FbFc06aDC17), Torex(0x269F9EF6868F70fB20DDF7CfDf69Fe1DBFD307dE)
        );
    }

    function _testBLMTorexWithReward(Torex torex1, Torex torex2) internal {
        TorexConfig memory torexConfig = torex1.getConfig();
        ISuperToken inToken = torexConfig.inToken;
        ISuperToken outToken = torexConfig.outToken;

        address rewardAddress = vm.addr(123);

        assertEq(outToken.balanceOf(rewardAddress), 0, "Reward address should start with no funds.");
        assertEq(inToken.balanceOf(rewardAddress), 0, "Reward address should start with no funds.");

        // uint256 torexInTokenBalanceBefore = inToken.balanceOf(address(torex));

        blm.moveLiquidityForReward(torex1, rewardAddress, 1);
        blm.moveLiquidityForReward(torex2, rewardAddress, 1);

        console2.log("BLM : outToken balance of reward address", outToken.balanceOf(rewardAddress));
        console2.log("BLM : inToken balance of reward address", inToken.balanceOf(rewardAddress));
        console2.log("BLM : outToken address", address(outToken));
        console2.log("BLM : inToken address", address(inToken));
        // assertGt(outToken.balanceOf(rewardAddress), 0, "Reward address balance should increase.");

        // assertGt(
        //     torexInTokenBalanceBefore,
        //     inToken.balanceOf(address(torex)),
        //     "The in tokens of TOREX should increase as they get used."
        // );

        // uint8 inTokenDecimals = inToken.getUnderlyingDecimals();
        // if (inTokenDecimals < 18) {
        //     assertLte(inToken.balanceOf(address(sut)), 1_000_000_000_000, "There is too much out token dust in the
        // LM.");
        // } else {
        //     assertLte(inToken.balanceOf(address(sut)), 0, "There is too much out token dust in the LM.");
        // }

        // assertEq(outToken.balanceOf(address(sut)), 0, "No out token should be left in the LM.");
    }

    function _testTTLMTorexWithReward(Torex torex1, Torex torex2) internal {
        TorexConfig memory torexConfig = torex1.getConfig();
        ISuperToken inToken = torexConfig.inToken;
        ISuperToken outToken = torexConfig.outToken;

        address rewardAddress = vm.addr(123);

        assertEq(outToken.balanceOf(rewardAddress), 0, "Reward address should start with no funds.");
        assertEq(inToken.balanceOf(rewardAddress), 0, "Reward address should start with no funds.");

        // uint256 torexInTokenBalanceBefore = inToken.balanceOf(address(torex));

        ttlm.moveLiquidityForReward(torex1, torex2, rewardAddress, 1);

        console2.log("TTLM : outToken balance of reward address", outToken.balanceOf(rewardAddress));
        console2.log("TTLM : inToken balance of reward address", inToken.balanceOf(rewardAddress));
        console2.log("TTLM : outToken address", address(outToken));
        console2.log("TTLM : inToken address", address(inToken));

        // assertGt(outToken.balanceOf(rewardAddress), 0, "Reward address balance should increase.");

        // assertGt(
        //     torexInTokenBalanceBefore,
        //     inToken.balanceOf(address(torex)),
        //     "The in tokens of TOREX should increase as they get used."
        // );

        // uint8 inTokenDecimals = inToken.getUnderlyingDecimals();
        // if (inTokenDecimals < 18) {
        //     assertLte(inToken.balanceOf(address(sut)), 1_000_000_000_000, "There is too much out token dust in the
        // LM.");
        // } else {
        //     assertLte(inToken.balanceOf(address(sut)), 0, "There is too much out token dust in the LM.");
        // }

        // assertEq(outToken.balanceOf(address(sut)), 0, "No out token should be left in the LM.");
    }
}
