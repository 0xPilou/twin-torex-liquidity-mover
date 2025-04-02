pragma solidity ^0.8.24;

import { ISuperToken } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperToken.sol";
import { ITwapObserver } from "./ITwapObserver.sol";

struct TorexConfig {
    ISuperToken inToken;
    ISuperToken outToken;
    ITwapObserver observer;
    uint256 discountFactor;
    int256 twapScaler;
    int256 outTokenDistributionPoolScaler;
    address controller;
    int256 maxAllowedFeePM;
}

interface ITorex {
    function getBenchmarkQuote(uint256 inAmount) external view returns (uint256);
    function moveLiquidity(bytes calldata moverData) external;
    function getConfig() external view returns (TorexConfig memory);
    function getLiquidityEstimations()
        external
        view
        returns (uint256 inAmount, uint256 minOutAmount, uint256 durationSinceLastLME, uint256 twapSinceLastLME);
}
