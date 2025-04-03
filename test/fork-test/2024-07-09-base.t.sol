// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {PRBTest} from "@prb/test/PRBTest.sol";

import {ITorex, TorexConfig} from "src/interfaces/superboring/ITorex.sol";

import {SwapRouter02LiquidityMover} from "src/SwapRouter02LiquidityMover.sol";
import {Deploy} from "script/Deploy.s.sol";

import {ISuperToken} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperToken.sol";

contract LiquidityMoverTests is PRBTest {
    Deploy deployScript;
    SwapRouter02LiquidityMover internal sut;

    function _setUpForkAndSut(uint256 blockNumber) private {
        vm.createSelectFork({urlOrAlias: vm.envString("BASE_RPC"), blockNumber: blockNumber});
        deployScript = new Deploy();
        sut = deployScript.run();
    }

    function test_0x76BA7a8a4d8320c6E9D4542255Fb05268f1B48BE() external {
        _setUpForkAndSut(16_887_578);
        _testTorexWithReward(ITorex(0x76BA7a8a4d8320c6E9D4542255Fb05268f1B48BE));
    }

    function test_0x6a19Ee195D996B70667894E2dAE9D10EE4d3D969() external {
        _setUpForkAndSut(16_887_608);
        _testTorexWithReward(ITorex(0x6a19Ee195D996B70667894E2dAE9D10EE4d3D969));
    }

    function test_0x68E5E539374353445b03Ec87D2Abfe2C791dEebc() external {
        _setUpForkAndSut(16_887_518);
        _testTorexWithReward(ITorex(0x68E5E539374353445b03Ec87D2Abfe2C791dEebc));
    }

    function test_0x27aee792433e4C8faA55396f91EE4119D282a83A() external {
        _setUpForkAndSut(16_887_638);
        _testTorexWithReward(ITorex(0x27aee792433e4C8faA55396f91EE4119D282a83A));
    }

    function test_0x6E0C1424108963425FB1Cca1829A7Cb610eecdb5() external {
        _setUpForkAndSut(16_887_668);
        _testTorexWithReward(ITorex(0x6E0C1424108963425FB1Cca1829A7Cb610eecdb5));
    }

    function test_0x0700d3BdBc8Fd357B28c209DAc74C23242B343C7() external {
        _setUpForkAndSut(16_887_548);
        _testTorexWithReward(ITorex(0x0700d3BdBc8Fd357B28c209DAc74C23242B343C7));
    }

    function test_0x598aF5742B4a6aBd7b66B2aEDd3Da17690ab72f2() external {
        _setUpForkAndSut(16_887_698);
        _testTorexWithReward(ITorex(0x598aF5742B4a6aBd7b66B2aEDd3Da17690ab72f2));
    }

    function test_0x16dF7D980198861Ba701C47C7D5E9Cb2D6bf7F8f() external {
        _setUpForkAndSut(16_887_728);
        _testTorexWithReward(ITorex(0x16dF7D980198861Ba701C47C7D5E9Cb2D6bf7F8f));
    }

    function test_0x267264CFB67B015ea23c97C07d609FbFc06aDC17() external {
        _setUpForkAndSut(16_887_458);
        _testTorexWithReward(ITorex(0x267264CFB67B015ea23c97C07d609FbFc06aDC17));
    }

    function test_0x9b3E9D6aF3fec387AbC9733c33a113fBb5Ed21ee() external {
        _setUpForkAndSut(16_886_858);
        _testTorexWithReward(ITorex(0x9b3E9D6aF3fec387AbC9733c33a113fBb5Ed21ee));
    }

    function test_0x43dc12CA897e6533e78B33b43e6993597D09DD73() external {
        _setUpForkAndSut(16_886_889);
        _testTorexWithReward(ITorex(0x43dc12CA897e6533e78B33b43e6993597D09DD73));
    }

    function test_0x269F9EF6868F70fB20DDF7CfDf69Fe1DBFD307dE() external {
        _setUpForkAndSut(16_897_388);
        _testTorexWithReward(ITorex(0x269F9EF6868F70fB20DDF7CfDf69Fe1DBFD307dE));
    }

    function _testTorexWithReward(ITorex torex) internal {
        TorexConfig memory torexConfig = torex.getConfig();
        ISuperToken inToken = torexConfig.inToken;
        ISuperToken outToken = torexConfig.outToken;
        address rewardAddress = vm.addr(123);

        assertEq(outToken.balanceOf(rewardAddress), 0, "Reward address should start with no funds.");

        uint256 torexInTokenBalanceBefore = inToken.balanceOf(address(torex));

        sut.moveLiquidityForReward(torex, rewardAddress, 1);

        assertGt(outToken.balanceOf(rewardAddress), 0, "Reward address balance should increase.");

        assertGt(
            torexInTokenBalanceBefore,
            inToken.balanceOf(address(torex)),
            "The in tokens of TOREX should increase as they get used."
        );

        uint8 inTokenDecimals = inToken.getUnderlyingDecimals();
        if (inTokenDecimals < 18) {
            assertLte(inToken.balanceOf(address(sut)), 1_000_000_000_000, "There is too much out token dust in the LM.");
        } else {
            assertLte(inToken.balanceOf(address(sut)), 0, "There is too much out token dust in the LM.");
        }

        assertEq(outToken.balanceOf(address(sut)), 0, "No out token should be left in the LM.");
    }
}
