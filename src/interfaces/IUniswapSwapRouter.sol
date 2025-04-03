pragma solidity ^0.8.24;

import {IPeripheryImmutableState} from "@uniswap/v3-periphery/contracts/interfaces/IPeripheryImmutableState.sol";
import {IV3SwapRouter} from "@uniswap/swap-router-contracts/contracts/interfaces/IV3SwapRouter.sol";

interface IUniswapSwapRouter is IV3SwapRouter, IPeripheryImmutableState {}
