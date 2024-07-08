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

// TODO: get from SuperBoring repo
/**
 * @dev Interface for the Liquidity Mover contracts.
 */
interface ILiquidityMover {
    /**
     * @dev Request out token liquidity, given an amount of in token has been already been transferred to the contract.
     * @param inToken   The in token transferred to the contract.
     * @param outToken  The out token that is requested.
     * @param inAmount     The amount of in token that has been transferred to the contract.
     * @param minOutAmount The amount of out token that is requested.
     * @return Always true.
     */
    function moveLiquidityCallback(
        ISuperToken inToken,
        ISuperToken outToken,
        uint256 inAmount,
        uint256 minOutAmount,
        bytes calldata moverData
    )
        external
        returns (bool);
}

// TODO: get from SuperBoring repo
interface Torex {
    function getBenchmarkQuote(uint256 inAmount) external view returns (uint256);
    function moveLiquidity(bytes calldata moverData) external;
    function getConfig() external view returns (Config memory);
}

// TODO: get from SuperBoring repo
interface ITwapObserver {
    /**
     * @dev Get the type id of the observer.
     *
     * Note:
     *   - This is useful for safe down-casting to the actual implementation.
     */
    function getTypeId() external view returns (bytes32); // keccak
        // 0xac2a7a01d08bec8d803b8d20516dcd7baca72524f2400f9e19acb905302f03e4 for UniswapV3PoolTwapObserver
}

// TODO: get from SuperBoring repo
interface IUniswapV3PoolTwapObserver is ITwapObserver {
    function uniPool() external view returns (IUniswapV3Pool);
}

// TODO: get from SuperBoring repo
struct Config {
    ISuperToken inToken;
    ISuperToken outToken;
    ITwapObserver observer;
    uint256 discountFactor;
    int256 twapScaler;
    int256 outTokenDistributionPoolScaler;
    address controller;
    int256 maxAllowedFeePM;
}

interface IUniswapSwapRouter is IV3SwapRouter, IPeripheryImmutableState { }

abstract contract UniswapLiquidityMover is ILiquidityMover {
    uint8 private constant SUPERTOKEN_DECIMALS = 18;

    IUniswapSwapRouter public immutable swapRouter;
    IWETH9 public immutable WETH;
    ISETH public immutable SETH;
    IERC20 public immutable ERC20ETH;

    enum SuperTokenType {
        Pure,
        Wrapper,
        NativeAsset
    }

    struct TransientStorage {
        Torex torex;
        IUniswapV3PoolTwapObserver observer;
        ISuperToken inToken;
        ISuperToken outToken;
        IERC20 swapInToken;
        uint256 swapInAmount;
        SuperTokenType outTokenType;
        IERC20 swapOutToken;
        uint256 swapOutAmountMinimum;
        uint256 swapOutAmountReceived;
    }

    /**
     * @param _swapRouter02 Make sure it's "SwapRouter02"!!! Not just "SwapRouter".
     * @param _nativeAssetSuperToken The chain's Native Asset Super Token (aka ETHx or SETH).
     * @param _nativeAssetERC20 The chain's ERC20 for Native Asset (not necessarily WETH).
     */
    constructor(
        IUniswapSwapRouter _swapRouter02,
        // Uniswap addresses available here: https://docs.uniswap.org/contracts/v3/reference/deployments (e.g.
        // 0xE592427A0AEce92De3Edee1F18E0157C05861564 for swap router)
        ISETH _nativeAssetSuperToken,
        IERC20 _nativeAssetERC20
    ) {
        swapRouter = _swapRouter02;
        SETH = _nativeAssetSuperToken;

        ERC20ETH = _nativeAssetERC20;
        WETH = IWETH9(_swapRouter02.WETH9());
        // Note that native asset ERC20 usage will take priority over WETH when handling Native Asset Super Tokens.

        if (address(ERC20ETH) == address(0) && address(WETH) == address(0)) {
            revert("LiquidityMover: Don't know how to handle native asset ERC20.");
        }
    }

    receive() external payable { }

    function _initializeTransientStorage(Torex torex) internal view returns (TransientStorage memory store) {
        store.torex = torex;

        Config memory torexConfig = store.torex.getConfig();
        store.observer = IUniswapV3PoolTwapObserver(address(torexConfig.observer));

        store.inToken = torexConfig.inToken;
        store.outToken = torexConfig.outToken;

        require(
            store.observer.getTypeId() == keccak256("UniswapV3PoolTwapObserver"),
            "LiquidityMover: unsupported observer type. This liquidity mover only for for Uniswap-based TWAP observers."
        );
    }

    function _swap(
        IERC20 swapInToken,
        uint256 swapInAmount,
        IERC20 swapOutToken,
        uint256 swapOutAmountMinimum,
        uint24 uniswapPoolFee
    )
        internal
        returns (uint256 swapOutAmountReceived)
    {
        // # Swap
        // Give swap router maximum allowance if necessary.
        if (swapInToken.allowance(address(this), address(swapRouter)) < swapInAmount) {
            TransferHelper.safeApprove(address(swapInToken), address(swapRouter), type(uint256).max);
        }

        // Single swap guide about Swap Router: https://docs.uniswap.org/contracts/v3/guides/swaps/single-swaps
        IV3SwapRouter.ExactInputSingleParams memory params = IV3SwapRouter.ExactInputSingleParams({
            tokenIn: address(swapInToken),
            tokenOut: address(swapOutToken),
            recipient: address(this),
            amountIn: swapInAmount,
            amountOutMinimum: swapOutAmountMinimum,
            fee: uniswapPoolFee,
            sqrtPriceLimitX96: 0
        });

        return swapRouter.exactInputSingle(params);
    }

    function _prepareInToken(
        ISuperToken inToken,
        uint256 inAmount
    )
        internal
        returns (IERC20 swapInToken, uint256 swapInAmount)
    {
        uint256 inTokenBalance = inToken.balanceOf(address(this));
        assert(inTokenBalance >= inAmount); // We always expect the inAmount to be transferred to this contract.

        (SuperTokenType inTokenType, address inTokenUnderlyingToken) = _getSuperTokenType(inToken);
        if (inTokenType == SuperTokenType.Wrapper) {
            inToken.downgrade(inTokenBalance);
            // Note that this can leave some dust behind when underlying token decimals differ.
            swapInToken = IERC20(inTokenUnderlyingToken);
        } else if (inTokenType == SuperTokenType.NativeAsset) {
            ISETH(address(inToken)).downgradeToETH(inTokenBalance);
            if (address(WETH) != address(0)) {
                WETH.deposit{ value: address(this).balance }();
                swapInToken = WETH;
            } else {
                swapInToken = ERC20ETH;
            }
        } else {
            // Pure Super Token
            swapInToken = inToken;
        }
        swapInAmount = swapInToken.balanceOf(address(this));
    }

    function _prepareOutToken(
        ISuperToken outToken,
        uint256 outAmount
    )
        internal
        view
        returns (
            SuperTokenType outTokenType,
            IERC20 swapOutToken,
            uint256 swapOutAmountMinimum,
            uint256 outAmountAdjusted
        )
    {
        address outTokenUnderlyingToken;
        (outTokenType, outTokenUnderlyingToken) = _getSuperTokenType(outToken);

        if (outTokenType == SuperTokenType.Wrapper) {
            swapOutToken = IERC20(outTokenUnderlyingToken);
            outAmountAdjusted = _adjustOutAmount(outAmount, outToken.getUnderlyingDecimals());
            (swapOutAmountMinimum,) = outToken.toUnderlyingAmount(outAmountAdjusted);
        } else if (outTokenType == SuperTokenType.NativeAsset) {
            if (address(WETH) != address(0)) {
                swapOutToken = WETH;
            } else {
                swapOutToken = ERC20ETH;
            }
            outAmountAdjusted = outAmount;
            swapOutAmountMinimum = outAmount;
        } else {
            // Pure Super Token
            swapOutToken = outToken;
            outAmountAdjusted = outAmount;
            swapOutAmountMinimum = outAmount;
        }
    }

    function _payTorexOutTokens(TransientStorage memory store, uint256 paymentAmount) internal {
        if (store.outTokenType == SuperTokenType.Wrapper) {
            if (store.swapOutToken.allowance(address(this), address(store.outToken)) < paymentAmount) {
                TransferHelper.safeApprove(address(store.swapOutToken), address(store.outToken), type(uint256).max);
            }
            store.outToken.upgradeTo(
                address(store.torex),
                _toSuperTokenAmount(paymentAmount, store.outToken.getUnderlyingDecimals()),
                bytes("")
            );
            // Reminder that `upgradeTo` expects Super Token decimals.
        } else if (store.outTokenType == SuperTokenType.NativeAsset) {
            if (address(store.swapOutToken) == address(WETH)) {
                WETH.withdraw(paymentAmount);
            }
            ISETH(address(store.outToken)).upgradeByETHTo{ value: paymentAmount }(address(store.torex));
        } else {
            // Pure Super Token
            TransferHelper.safeTransfer(address(store.outToken), address(store.torex), paymentAmount);
        }
    }

    function _getSuperTokenType(ISuperToken superToken)
        internal
        view
        returns (SuperTokenType, address underlyingTokenAddress)
    {
        // TODO: Allow for optimization from off-chain set-up?
        bool isNativeAssetSuperToken = address(superToken) == address(SETH);
        if (isNativeAssetSuperToken) {
            return (SuperTokenType.NativeAsset, address(0));
            // Note that there are a few exceptions where Native Asset Super Tokens have an underlying token,
            // but we don't want to use it for simplification reasons, hence we don't return it.
        } else {
            address underlyingToken = superToken.getUnderlyingToken();
            if (underlyingToken != address(0)) {
                return (SuperTokenType.Wrapper, underlyingToken);
            } else {
                return (SuperTokenType.Pure, address(0));
            }
        }
    }

    function _adjustOutAmount(
        uint256 outAmount, // 18 decimals
        uint8 underlyingTokenDecimals
    )
        internal
        pure
        returns (uint256 outAmountAdjusted)
    {
        if (underlyingTokenDecimals < SUPERTOKEN_DECIMALS) {
            uint256 factor = 10 ** (SUPERTOKEN_DECIMALS - underlyingTokenDecimals);
            outAmountAdjusted = ((outAmount / factor) + 1) * factor; // Effectively rounding up.
        }
        // No need for adjustment when the underlying token has greater or equal decimals.
        else {
            outAmountAdjusted = outAmount;
        }
    }

    function _toSuperTokenAmount(
        uint256 underlyingAmount,
        uint8 underlyingDecimals
    )
        internal
        pure
        returns (uint256 superTokenAmount)
    {
        uint256 factor;
        if (underlyingDecimals < SUPERTOKEN_DECIMALS) {
            factor = 10 ** (SUPERTOKEN_DECIMALS - underlyingDecimals);
            superTokenAmount = underlyingAmount * factor;
        } else if (underlyingDecimals > SUPERTOKEN_DECIMALS) {
            factor = 10 ** (underlyingDecimals - SUPERTOKEN_DECIMALS);
            superTokenAmount = underlyingAmount / factor;
        } else {
            superTokenAmount = underlyingAmount;
        }
    }
}
