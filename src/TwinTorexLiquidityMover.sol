// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ILiquidityMover} from "./interfaces/superboring/ILiquidityMover.sol";
import {ITorex} from "./interfaces/superboring/ITorex.sol";
import {ISuperToken} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperToken.sol";

contract TwinTorexLiquidityMover is ILiquidityMover {
    address private transient _liquiditySource;
    address private transient _richTorex;
    address private transient _poorTorex;

    error INVALID_INVOKER();
    error INVALID_TWIN_TOREX_SETUP();

    function moveLiquidity(ITorex torex0, ITorex torex1) external {
        _moveLiquidity(torex0, torex1);
    }

    function _moveLiquidity(ITorex torex0, ITorex torex1) internal {
        // Get the liquidity estimations for the both Torexes
        (uint256 t0InAmount, uint256 t0MinOutAmount,,) = torex0.getLiquidityEstimations();
        (uint256 t1InAmount, uint256 t1MinOutAmount,,) = torex1.getLiquidityEstimations();

        // Define which Torex (RichTorex) can pay for its twin Torex (PoorTorex) LME.
        if (t0InAmount >= t1MinOutAmount) {
            _richTorex = address(torex0);
            _poorTorex = address(torex1);
        } else if (t1InAmount >= t0MinOutAmount) {
            _richTorex = address(torex1);
            _poorTorex = address(torex0);
        } else {
            revert INVALID_TWIN_TOREX_SETUP();
        }

        _liquiditySource = msg.sender;

        // Initiate LME for the Rich Torex
        ITorex(_richTorex).moveLiquidity(bytes(""));
    }

    /// @inheritdoc ILiquidityMover
    function moveLiquidityCallback(
        ISuperToken inToken,
        ISuperToken outToken,
        uint256 inAmount,
        uint256 minOutAmount,
        bytes calldata
    ) external returns (bool success) {
        if (msg.sender == _richTorex) {
            // perform the poor torex LME
            ITorex(_poorTorex).moveLiquidity(bytes(""));

            // then continue the rich torex LME
            uint256 outTokenBalance = outToken.balanceOf(address(this));

            if (outTokenBalance > minOutAmount) {
                // Transfer the excess outToken to the liquidity source
                outToken.transfer(_liquiditySource, outTokenBalance - minOutAmount);
            } else if (outTokenBalance < minOutAmount) {
                // Transfer the missing outToken from the liquidity source
                outToken.transferFrom(_liquiditySource, address(this), minOutAmount - outTokenBalance);
            }

            // Transfer the outToken to the rich torex
            outToken.transfer(msg.sender, minOutAmount);

            // Transfer the inToken to the liquidity source
            inToken.transfer(_liquiditySource, inAmount);
        } else if (msg.sender == _poorTorex) {
            // Transfer the outToken to the poor torex from the LM
            outToken.transfer(msg.sender, minOutAmount);
        } else {
            revert INVALID_INVOKER();
        }

        success = true;
    }
}
