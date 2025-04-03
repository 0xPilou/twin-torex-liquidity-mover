// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ITorex, TorexConfig} from "../../src/interfaces/superboring/ITorex.sol";
import {ILiquidityMover} from "../../src/interfaces/superboring/ILiquidityMover.sol";
import {ISuperToken} from "@superfluid-finance/ethereum-contracts/contracts/superfluid/SuperToken.sol";

// Mock Torex for testing
contract MockTorex is ITorex {
    ISuperToken public immutable inToken;
    ISuperToken public immutable outToken;

    uint256 public currentInAmount;
    uint256 public currentMinOutAmount;

    constructor(ISuperToken _inToken, ISuperToken _outToken) {
        inToken = _inToken;
        outToken = _outToken;
    }

    function moveLiquidity(bytes calldata data) external override {
        inToken.transfer(msg.sender, currentInAmount);
        ILiquidityMover(msg.sender).moveLiquidityCallback(inToken, outToken, currentInAmount, currentMinOutAmount, data);

        currentInAmount = 0;
        currentMinOutAmount = 0;
    }

    function getLiquidityEstimations()
        external
        view
        returns (uint256 inAmount, uint256 minOutAmount, uint256 durationSinceLastLME, uint256 twapSinceLastLME)
    {
        inAmount = currentInAmount;
        minOutAmount = currentMinOutAmount;
        durationSinceLastLME = 0;
        twapSinceLastLME = 0;
    }

    function getBenchmarkQuote(uint256 inAmount) external view returns (uint256) {}
    function getConfig() external view returns (TorexConfig memory) {}

    function setAmounts(uint256 _inAmount, uint256 _minOutAmount) external {
        currentInAmount = _inAmount;
        currentMinOutAmount = _minOutAmount;
    }
}
