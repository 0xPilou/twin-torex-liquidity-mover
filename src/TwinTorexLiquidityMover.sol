// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.15; // TODO: Forced this because IWETH9 required 0.8.15.

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { TransferHelper } from "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import { IV3SwapRouter } from "@uniswap/swap-router-contracts/contracts/interfaces/IV3SwapRouter.sol";

import { ISuperToken } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperToken.sol";
import { ISETH } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/tokens/ISETH.sol";

import {
    IUniswapSwapRouter,
    IWETH9,
    Torex,
    ITwapObserver,
    IUniswapV3PoolTwapObserver,
    TorexConfig,
    ILiquidityMover
} from "./ILiquidityMover.sol";

contract TwinTorexLiquidityMover is ILiquidityMover {
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

    struct Context {
        Torex richTorex;
        Torex poorTorex;
        bytes richTorexSwapPath;
        ITwapObserver richTorexObserver;
        address rewardAddress;
        uint256 rewardAmountMinimum;
    }

    event LiquidityMoverFinished(
        address indexed torex,
        address indexed rewardAddress,
        address inToken,
        uint256 inAmount,
        address outToken,
        uint256 minOutAmount,
        uint256 outAmountActual,
        uint256 rewardAmount
    );

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

    function moveLiquidity(Torex torex0, Torex torex1) external {
        _moveLiquidity(torex0, torex1, address(0), 0, bytes(""));
    }

    function moveLiquidityForReward(
        Torex torex0,
        Torex torex1,
        address rewardAddress,
        uint256 rewardAmountMinimum
    )
        external
    {
        _moveLiquidity(torex0, torex1, rewardAddress, rewardAmountMinimum, bytes(""));
    }

    function _moveLiquidity(
        Torex torex0,
        Torex torex1,
        address rewardAddress,
        uint256 rewardAmountMinimum,
        bytes memory swapPath
    )
        private
    {
        (uint256 t0InAmount, uint256 t0MinOutAmount,,) = torex0.getLiquidityEstimations();
        (uint256 t1InAmount, uint256 t1MinOutAmount,,) = torex1.getLiquidityEstimations();

        Torex richTorex;
        Torex poorTorex;

        // Here we determine which Torex (RichTorex) can pay for its twin Torex (PoorTorex) LME.
        if (t0InAmount >= t1MinOutAmount) {
            richTorex = torex0;
            poorTorex = torex1;
        } else if (t1InAmount >= t0MinOutAmount) {
            richTorex = torex1;
            poorTorex = torex0;
        } else {
            revert("TwinTorexLiquidityMover: No valid Torex pair found");
        }

        Context memory ctx = _initializeContext(richTorex, poorTorex, rewardAddress, rewardAmountMinimum, swapPath);
        richTorex.moveLiquidity(abi.encode(ctx));
    }

    function moveLiquidityCallback(
        ISuperToken inToken,
        ISuperToken outToken,
        uint256,
        uint256 minOutAmount,
        bytes calldata moverData
    )
        external
        override
        returns (bool)
    {
        Context memory ctx = abi.decode(moverData, (Context));

        // If we are in the Rich Torex callback, we need to perform the poor Torex LME
        if (msg.sender == address(ctx.richTorex)) {
            ctx.poorTorex.moveLiquidity(abi.encode(ctx));
            /// NOTE: at this points the poor torex LME is completed

            // Finish the Rich Torex LME
            if (outToken.balanceOf(address(this)) >= minOutAmount) {
                // If Poor Torex LME granted us with enough Rich Torex OutToken, we can finish the Rich Torex LME
                TransferHelper.safeTransfer(address(outToken), msg.sender, minOutAmount);
            } else {
                // Otherwise we need to swap some of the inToken to outToken to pay the Rich Torex

                // # Prepare In and Out Tokens
                // It means unwrapping and converting them to ERC-20s that the swap router understands.
                (IERC20 swapInToken, uint256 swapInAmount) =
                    _prepareInTokenForSwap(inToken, inToken.balanceOf(address(this)));
                (SuperTokenType outTokenType, IERC20 swapOutToken, uint256 swapOutAmountMinimum) =
                    _prepareOutTokenForSwap(outToken, outToken.balanceOf(address(this)));
                // _prepareOutTokenForSwap(outToken, minOutAmount - outToken.balanceOf(address(this)));

                // # Swap
                // Give swap router maximum allowance if necessary.
                if (swapInToken.allowance(address(this), address(swapRouter)) < swapInAmount) {
                    TransferHelper.safeApprove(address(swapInToken), address(swapRouter), type(uint256).max);
                }

                // Set default swap path if not specified explicitly.
                // if (ctx.richTorexSwapPath.length == 0) {
                //     require(
                //         ctx.richTorexObserver.getTypeId() == keccak256("UniswapV3PoolTwapObserver"),
                //         "LiquidityMover: when trade path is not provided, observer must be a
                // UniswapV3PoolTwapObserver to determine the default swap path."
                //     );
                //     ctx.richTorexSwapPath = abi.encodePacked(
                //         address(swapOutToken),
                //         IUniswapV3PoolTwapObserver(address(ctx.richTorexObserver)).uniPool().fee(),
                //         address(swapInToken)
                //     );
                // }

                // // Single swap guide about Swap Router:
                // https://docs.uniswap.org/contracts/v3/guides/swaps/single-swaps
                // swapRouter.exactOutput(
                //     IV3SwapRouter.ExactOutputParams({
                //         path: ctx.richTorexSwapPath,
                //         recipient: address(this),
                //         amountOut: swapOutAmountMinimum,
                //         amountInMaximum: swapInAmount
                //     })
                // );

                if (ctx.richTorexSwapPath.length == 0) {
                    require(
                        ctx.richTorexObserver.getTypeId() == keccak256("UniswapV3PoolTwapObserver"),
                        "LiquidityMover: when trade path is not provided, observer must be a UniswapV3PoolTwapObserver to determine the default swap path."
                    );
                    ctx.richTorexSwapPath = abi.encodePacked(
                        address(swapInToken),
                        IUniswapV3PoolTwapObserver(address(ctx.richTorexObserver)).uniPool().fee(),
                        address(swapOutToken)
                    );
                }

                // Single swap guide about Swap Router: https://docs.uniswap.org/contracts/v3/guides/swaps/single-swaps
                swapRouter.exactInput(
                    IV3SwapRouter.ExactInputParams({
                        path: ctx.richTorexSwapPath,
                        recipient: address(this),
                        amountIn: swapInAmount,
                        amountOutMinimum: swapOutAmountMinimum
                    })
                );

                // Update all the tokens directly to TOREX.
                _upgradeAllTokensToOutTokensIfNecessary(swapOutToken, outToken, outTokenType, address(this));

                TransferHelper.safeTransfer(address(outToken), address(ctx.richTorex), minOutAmount);
                TransferHelper.safeTransfer(address(inToken), ctx.rewardAddress, inToken.balanceOf(address(this)));
                TransferHelper.safeTransfer(address(outToken), ctx.rewardAddress, outToken.balanceOf(address(this)));
            }
        } else if (msg.sender == address(ctx.poorTorex)) {
            // Transfer the outToken amount to the Poor Torex
            TransferHelper.safeTransfer(address(outToken), msg.sender, minOutAmount);
        } else {
            revert("TwinTorexLiquidityMover: Invalid callback sender");
        }

        return true;
    }

    function _initializeContext(
        Torex richTorex,
        Torex poorTorex,
        address rewardAddress,
        uint256 rewardAmountMinimum,
        bytes memory swapPath
    )
        internal
        view
        returns (Context memory ctx)
    {
        ctx.richTorex = richTorex;
        ctx.poorTorex = poorTorex;
        ctx.rewardAddress = rewardAddress;
        ctx.rewardAmountMinimum = rewardAmountMinimum;
        ctx.richTorexSwapPath = swapPath;

        TorexConfig memory richTorexConfig = ctx.richTorex.getConfig();
        ctx.richTorexObserver = ITwapObserver(address(richTorexConfig.observer));
    }

    function _prepareInTokenForSwap(
        ISuperToken inToken,
        uint256 inAmount
    )
        private
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

    function _prepareOutTokenForSwap(
        ISuperToken outToken,
        uint256 outAmount
    )
        private
        view
        returns (SuperTokenType outTokenType, IERC20 swapOutToken, uint256 swapOutAmountMinimum)
    {
        address outTokenUnderlyingToken;
        (outTokenType, outTokenUnderlyingToken) = _getSuperTokenType(outToken);

        if (outTokenType == SuperTokenType.Wrapper) {
            swapOutToken = IERC20(outTokenUnderlyingToken);
            uint256 outAmountRoundedUp = _roundUpOutAmount(outAmount, outToken.getUnderlyingDecimals());
            (swapOutAmountMinimum,) = outToken.toUnderlyingAmount(outAmountRoundedUp);
        } else if (outTokenType == SuperTokenType.NativeAsset) {
            if (address(WETH) != address(0)) {
                swapOutToken = WETH;
            } else {
                swapOutToken = ERC20ETH;
            }
            swapOutAmountMinimum = outAmount;
        } else {
            // Pure Super Token
            swapOutToken = outToken;
            swapOutAmountMinimum = outAmount;
        }
    }

    function _upgradeAllTokensToOutTokensIfNecessary(
        IERC20 swapOutToken,
        ISuperToken outToken,
        SuperTokenType outTokenType,
        address to
    )
        private
        returns (uint256 outTokenAmount)
    {
        if (outTokenType == SuperTokenType.Wrapper) {
            // Give Super Token maximum allowance if necessary.
            uint256 swapOutTokenBalance = swapOutToken.balanceOf(address(this));
            if (swapOutToken.allowance(address(this), address(outToken)) < swapOutTokenBalance) {
                TransferHelper.safeApprove(address(swapOutToken), address(outToken), type(uint256).max);
            }
            outTokenAmount = _toSuperTokenAmount(swapOutTokenBalance, outToken.getUnderlyingDecimals());
            outToken.upgradeTo(to, outTokenAmount, bytes(""));
            // Reminder that `upgradeTo` expects Super Token decimals.
            // Small dust mount might remain here.
        } else if (outTokenType == SuperTokenType.NativeAsset) {
            if (address(WETH) != address(0)) {
                WETH.withdraw(WETH.balanceOf(address(this)));
            }
            outTokenAmount = address(this).balance;
            ISETH(address(outToken)).upgradeByETHTo{ value: outTokenAmount }(to);
        } else {
            // Pure Super Token
            outTokenAmount = outToken.balanceOf(address(this));
            if (to != address(this)) {
                // Only makes sense to transfer if destination is other than current address.
                TransferHelper.safeTransfer(address(outToken), to, outTokenAmount);
            }
        }
    }

    function _getSuperTokenType(ISuperToken superToken)
        private
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

    function _roundUpOutAmount(
        uint256 outAmount, // 18 decimals
        uint8 underlyingTokenDecimals
    )
        private
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
        private
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
