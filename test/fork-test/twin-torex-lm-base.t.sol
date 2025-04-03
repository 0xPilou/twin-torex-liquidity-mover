// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {PRBTest} from "@prb/test/PRBTest.sol";

import {ITorex, TorexConfig} from "src/interfaces/superboring/ITorex.sol";
import {console2} from "forge-std/console2.sol";

import {UniswapV3TwinTorexLiquidityMover} from "src/UniswapV3TwinTorexLiquidityMover.sol";
import {SwapRouter02LiquidityMover} from "src/SwapRouter02LiquidityMover.sol";
import {DeployTTLM} from "script/DeployTTLM.s.sol";
import {Deploy} from "script/Deploy.s.sol";

import {ISuperToken} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperToken.sol";

contract TTLiquidityMoverTests is PRBTest {
    DeployTTLM deployTTLMScript;
    Deploy deployBLMScript;
    UniswapV3TwinTorexLiquidityMover internal ttlm;
    SwapRouter02LiquidityMover internal blm;

    function _setUpForkAndSut(uint256 blockNumber) private {
        vm.createSelectFork({urlOrAlias: vm.envString("BASE_RPC"), blockNumber: blockNumber});
        deployTTLMScript = new DeployTTLM();
        deployBLMScript = new Deploy();
        ttlm = deployTTLMScript.run();
        blm = deployBLMScript.run();
    }

    function test_twinTorexLM_ETH_USDC() external {
        _setUpForkAndSut(27_578_099);
        _testTTLMTorexWithReward(
            ITorex(0x267264CFB67B015ea23c97C07d609FbFc06aDC17),
            ITorex(0x269F9EF6868F70fB20DDF7CfDf69Fe1DBFD307dE),
            vm.addr(123)
        );
    }

    function test_basicLM_ETH_USDC() external {
        _setUpForkAndSut(27_578_099);
        _testBLMTorexWithReward(
            ITorex(0x267264CFB67B015ea23c97C07d609FbFc06aDC17),
            ITorex(0x269F9EF6868F70fB20DDF7CfDf69Fe1DBFD307dE),
            vm.addr(123)
        );
    }

    function test_twinTorexLM_ETH_WSTETH() external {
        _setUpForkAndSut(27_578_099);
        _testTTLMTorexWithReward(
            ITorex(0xd21549892BF317CCFe7fB220dcF14aB15dFE5428),
            ITorex(0x78EfCd2bc1175D69863b1c9aAC9996b766c07A3A),
            vm.addr(123)
        );
    }

    function test_basicLM_ETH_WSTETH() external {
        _setUpForkAndSut(27_578_099);
        _testBLMTorexWithReward(
            ITorex(0xd21549892BF317CCFe7fB220dcF14aB15dFE5428),
            ITorex(0x78EfCd2bc1175D69863b1c9aAC9996b766c07A3A),
            vm.addr(123)
        );
    }

    function test_twinTorexLM_USDC_cbBTC() external {
        _setUpForkAndSut(27_715_462);
        _testTTLMTorexWithReward(
            ITorex(0x9777e77E7813dc44EC9da7Bfca69042641eB56d9),
            ITorex(0xA8E5F011F72088E3113E2f4F8C3FB119Fc2E226C),
            vm.addr(123)
        );
    }

    function test_basicLM_USDC_cbBTC() external {
        _setUpForkAndSut(27_715_462);
        _testBLMTorexWithReward(
            ITorex(0x9777e77E7813dc44EC9da7Bfca69042641eB56d9),
            ITorex(0xA8E5F011F72088E3113E2f4F8C3FB119Fc2E226C),
            vm.addr(123)
        );
    }

    function _testBLMTorexWithReward(ITorex torex1, ITorex torex2, address rewardAddress) internal {
        TorexConfig memory torexConfig = torex1.getConfig();
        ISuperToken inToken = torexConfig.inToken;
        ISuperToken outToken = torexConfig.outToken;

        assertEq(outToken.balanceOf(rewardAddress), 0, "Reward address should start with no funds.");
        assertEq(inToken.balanceOf(rewardAddress), 0, "Reward address should start with no funds.");

        uint256 gasBefore = gasleft();

        blm.moveLiquidityForReward(torex1, rewardAddress, 1);
        blm.moveLiquidityForReward(torex2, rewardAddress, 1);

        console2.log("BLM - Token 0 :", outToken.name());
        console2.log("BLM - Token 1 :", inToken.name());

        console2.log("BLM - Token 0 - Reward Amount :", outToken.balanceOf(rewardAddress));
        console2.log("BLM - Token 1 - Reward Amount :", inToken.balanceOf(rewardAddress));
        console2.log("BLM - Gas used", gasBefore - gasleft());
    }

    function _testTTLMTorexWithReward(ITorex torex1, ITorex torex2, address rewardAddress) internal {
        TorexConfig memory torexConfig = torex1.getConfig();
        ISuperToken inToken = torexConfig.inToken;
        ISuperToken outToken = torexConfig.outToken;

        assertEq(outToken.balanceOf(rewardAddress), 0, "Reward address should start with no funds.");
        assertEq(inToken.balanceOf(rewardAddress), 0, "Reward address should start with no funds.");

        uint256 gasBefore = gasleft();

        ttlm.moveLiquidityForReward(torex1, torex2, rewardAddress, 1);

        console2.log("TTLM - Token 0 :", outToken.name());
        console2.log("TTLM - Token 1 :", inToken.name());

        console2.log("TTLM - Token 0 - Reward Amount :", outToken.balanceOf(rewardAddress));
        console2.log("TTLM - Token 1 - Reward Amount :", inToken.balanceOf(rewardAddress));
        console2.log("TTLM - Gas used", gasBefore - gasleft());
    }
}
