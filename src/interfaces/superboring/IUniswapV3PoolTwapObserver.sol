// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import { ITwapObserver } from "./ITwapObserver.sol";
import { IUniswapV3Pool } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

interface IUniswapV3PoolTwapObserver is ITwapObserver {
    function uniPool() external view returns (IUniswapV3Pool);
}
