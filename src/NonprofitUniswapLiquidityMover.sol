// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.15; // TODO: Forced this because IWETH9 required 0.8.15.

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IUniswapV3Pool } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import { TransferHelper } from "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import { IV3SwapRouter } from "@uniswap/swap-router-contracts/contracts/interfaces/IV3SwapRouter.sol";
import { IPeripheryImmutableState } from "@uniswap/v3-periphery/contracts/interfaces/IPeripheryImmutableState.sol";
import { IWETH9 } from "@uniswap/v3-periphery/contracts/interfaces/external/IWETH9.sol";

import { ISuperToken } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperToken.sol";
import { ISETHCustom, ISETH } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/tokens/ISETH.sol";

import { UniswapLiquidityMover, IUniswapSwapRouter, Torex } from "./LiquidityMover.sol";

contract NonprofitUniswapLiquidityMover is UniswapLiquidityMover {
    constructor(
        IUniswapSwapRouter _swapRouter02,
        ISETH _nativeAssetSuperToken,
        IERC20 _nativeAssetERC20
    )
        UniswapLiquidityMover(_swapRouter02, _nativeAssetSuperToken, _nativeAssetERC20)
    { }

    function moveLiquidity(Torex torex) external returns (bool) {
        torex.moveLiquidity(bytes(""));
        return true;
    }

    function moveLiquidityCallback(
        ISuperToken, /* inToken */
        ISuperToken, /* outToken */
        uint256 inAmount,
        uint256 minOutAmount,
        bytes calldata /* moverData */
    )
        // TODO: lock for re-entrancy?
        external
        override
        returns (bool)
    {
        TransientStorage memory store = _initializeTransientStorage(Torex(address(msg.sender)));

        // # Prepare In and Out Tokens
        // It means unwrapping and converting them to ERC-20s that the swap router understands.
        (store.swapInToken, store.swapInAmount) = _prepareInToken(store.inToken, inAmount);

        // We're happy passing everything into the swap.
        store.swapInAmount = store.swapInToken.balanceOf(address(this));

        (store.outTokenType, store.swapOutToken, store.swapOutAmountMinimum,) =
            _prepareOutToken(store.outToken, minOutAmount);

        // # Swap
        store.swapOutAmountReceived = _swap(
            store.swapInToken,
            store.swapInAmount,
            store.swapOutToken,
            store.swapOutAmountMinimum,
            store.observer.uniPool().fee()
        );

        // # Pay
        _payTorexOutTokens(store, store.swapOutToken.balanceOf(address(this)));

        return true;
    }
}
