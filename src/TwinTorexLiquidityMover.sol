// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

/* OpenZeppelin Imports */
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IWETH9 } from "./interfaces/IWETH9.sol";

/* UniswapV3 Imports */
import { TransferHelper } from "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import { IV3SwapRouter } from "@uniswap/swap-router-contracts/contracts/interfaces/IV3SwapRouter.sol";
import { IUniswapSwapRouter } from "./interfaces/IUniswapSwapRouter.sol";
/* Superfluid Imports */
import { ISuperToken } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperToken.sol";
import { ISETH } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/tokens/ISETH.sol";

/* Superboring Imports */
import { ITorex, TorexConfig } from "./interfaces/superboring/ITorex.sol";
import { ILiquidityMover } from "./interfaces/superboring/ILiquidityMover.sol";
import { ITwapObserver } from "./interfaces/superboring/ITwapObserver.sol";
import { IUniswapV3PoolTwapObserver } from "./interfaces/superboring/IUniswapV3PoolTwapObserver.sol";

/**
 * @title TwinTorexLiquidityMover Contract
 * @notice Contract responsible for moving liquidity between twin Torexes
 */
contract TwinTorexLiquidityMover is ILiquidityMover {
    //      ______                 __
    //     / ____/   _____  ____  / /______
    //    / __/ | | / / _ \/ __ \/ __/ ___/
    //   / /___ | |/ /  __/ / / / /_(__  )
    //  /_____/ |___/\___/_/ /_/\__/____/

    /**
     * @notice Emitted when a liquidity movement operation is completed
     * @param torex The Torex contract that liquidity was moved from/to
     * @param rewardAddress The address that received rewards for moving liquidity
     * @param inToken The input token address used in the operation
     * @param inAmount The amount of input tokens used
     * @param outToken The output token address received
     * @param minOutAmount The minimum output amount specified
     * @param outAmountActual The actual output amount received
     * @param rewardAmount The amount of rewards received by rewardAddress
     */
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

    //      ____        __        __
    //     / __ \____ _/ /_____ _/ /___  ______  ___  _____
    //    / / / / __ `/ __/ __ `/ __/ / / / __ \/ _ \/ ___/
    //   / /_/ / /_/ / /_/ /_/ / /_/ /_/ / /_/ /  __(__  )
    //  /_____/\__,_/\__/\__,_/\__/\__, / .___/\___/____/
    //                            /____/_/

    /**
     * @notice SuperToken Type enum
     * @param Pure Super Token
     * @param Wrapper Super Token with underlying token
     * @param NativeAsset Native Asset Super Token
     */
    enum SuperTokenType {
        Pure,
        Wrapper,
        NativeAsset
    }

    /**
     * @notice Context struct containing data needed for liquidity movement operations
     * @param richTorex The Torex with more liquidity that will be moved
     * @param poorTorex The Torex with less liquidity that will receive liquidity
     * @param richTorexSwapPath The encoded swap path for the rich Torex's tokens
     * @param richTorexObserver The TWAP observer contract for the rich Torex
     * @param rewardAddress The address that will receive rewards for moving liquidity
     * @param rewardAmountMinimum The minimum reward amount that must be received
     */
    struct Context {
        ITorex richTorex;
        ITorex poorTorex;
        bytes richTorexSwapPath;
        ITwapObserver richTorexObserver;
        address rewardAddress;
        uint256 rewardAmountMinimum;
    }

    //     ______           __                     ______
    //    / ____/_  _______/ /_____  ____ ___     / ____/_____________  __________
    //   / /   / / / / ___/ __/ __ \/ __ `__ \   / __/ / ___/ ___/ __ \/ ___/ ___/
    //  / /___/ /_/ (__  ) /_/ /_/ / / / / / /  / /___/ /  / /  / /_/ / /  (__  )
    //  \____/\__,_/____/\__/\____/_/ /_/ /_/  /_____/_/  /_/   \____/_/  /____/

    /// @notice Error emitted when trying to handle Native Asset
    /// @dev Error Selector : 0x9d1601f3
    error CANNOT_HANDLE_NATIVE_ASSETS();

    /// @notice Error emitted when trying to move liquidity between invalid twin Torex pair
    /// @dev Error Selector : 0x9cb921f2
    error INVALID_TWIN_TOREX_PAIR();

    /// @notice Error emitted when trying to move liquidity between invalid twin Torex setup
    /// @dev Error Selector : 0xe5c97e3e
    error INVALID_TWIN_TOREX_SETUP();

    /// @notice Error emitted when calling the callback with an invalid sender
    /// @dev Error Selector : 0xd9f8cdaf
    error SENDER_MUST_BE_TOREX();

    /// @notice Error emitted when an invalid TWAP observer is used
    /// @dev Error Selector : 0x33da402e
    error INVALID_TWAP_OBSERVER();

    //      ____                          __        __    __        _____ __        __
    //     /  _/___ ___  ____ ___  __  __/ /_____ _/ /_  / /__     / ___// /_____ _/ /____  _____
    //     / // __ `__ \/ __ `__ \/ / / / __/ __ `/ __ \/ / _ \    \__ \/ __/ __ `/ __/ _ \/ ___/
    //   _/ // / / / / / / / / / / /_/ / /_/ /_/ / /_/ / /  __/   ___/ / /_/ /_/ / /_/  __(__  )
    //  /___/_/ /_/ /_/_/ /_/ /_/\__,_/\__/\__,_/_.___/_/\___/   /____/\__/\__,_/\__/\___/____/

    /// @notice Super Token decimals
    uint8 private constant SUPERTOKEN_DECIMALS = 18;

    /// @notice Uniswap Swap Router interface
    IUniswapSwapRouter public immutable SWAP_ROUTER;

    /// @notice WETH interface
    IWETH9 public immutable WETH;

    /// @notice SuperToken Native Asset interface
    ISETH public immutable SETH;

    /// @notice Native Asset ERC20 interface
    IERC20 public immutable ERC20ETH;

    //     ______                 __                  __
    //    / ____/___  ____  _____/ /________  _______/ /_____  _____
    //   / /   / __ \/ __ \/ ___/ __/ ___/ / / / ___/ __/ __ \/ ___/
    //  / /___/ /_/ / / / (__  ) /_/ /  / /_/ / /__/ /_/ /_/ / /
    //  \____/\____/_/ /_/____/\__/_/   \__,_/\___/\__/\____/_/

    /**
     * @notice TwinTorexLiquidityMover constructor
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
        SWAP_ROUTER = _swapRouter02;
        SETH = _nativeAssetSuperToken;

        ERC20ETH = _nativeAssetERC20;
        WETH = IWETH9(_swapRouter02.WETH9());

        // Note : Native asset ERC20 usage will take priority over WETH when handling Native Asset Super Tokens.
        if (address(ERC20ETH) == address(0) && address(WETH) == address(0)) {
            revert CANNOT_HANDLE_NATIVE_ASSETS();
        }
    }

    //      ______     __                        __   ______                 __  _
    //     / ____/  __/ /____  _________  ____ _/ /  / ____/_  ______  _____/ /_(_)___  ____  _____
    //    / __/ | |/_/ __/ _ \/ ___/ __ \/ __ `/ /  / /_  / / / / __ \/ ___/ __/ / __ \/ __ \/ ___/
    //   / /____>  </ /_/  __/ /  / / / / /_/ / /  / __/ / /_/ / / / / /__/ /_/ / /_/ / / / (__  )
    //  /_____/_/|_|\__/\___/_/  /_/ /_/\__,_/_/  /_/    \__,_/_/ /_/\___/\__/_/\____/_/ /_/____/

    /**
     * @notice Allows the contract to receive native assets (ETH)
     * @dev Required for handling native asset operations and unwrapping WETH
     */
    receive() external payable { }

    /**
     * @notice Moves liquidity between two Torexes for a specific reward sent to the caller
     * @param torex0 The first Torex
     * @param torex1 The second Torex
     */
    function moveLiquidityForReward(ITorex torex0, ITorex torex1) external {
        _moveLiquidity(torex0, torex1, msg.sender, 0, bytes(""));
    }

    /**
     * @notice Moves liquidity between two Torexes for a specific reward address
     * @param torex0 The first Torex
     * @param torex1 The second Torex
     * @param rewardAddress The address that will receive the rewards
     * @param rewardAmountMinimum The minimum reward amount that must be received
     */
    function moveLiquidityForReward(
        ITorex torex0,
        ITorex torex1,
        address rewardAddress,
        uint256 rewardAmountMinimum
    )
        external
    {
        _moveLiquidity(torex0, torex1, rewardAddress, rewardAmountMinimum, bytes(""));
    }

    /**
     * @notice Moves liquidity between two Torexes for a reward sent to the caller with a custom swap path
     * @param torex0 The first Torex
     * @param torex1 The second Torex
     * @param swapPath The encoded swap path to use for token swaps
     */
    function moveLiquidityForRewardWithPath(ITorex torex0, ITorex torex1, bytes calldata swapPath) external {
        _moveLiquidity(torex0, torex1, msg.sender, 0, swapPath);
    }

    /**
     * @notice Moves liquidity between two Torexes for a specific reward address with a custom swap path
     * @param torex0 The first Torex
     * @param torex1 The second Torex
     * @param rewardAddress The address that will receive the rewards
     * @param rewardAmountMinimum The minimum reward amount that must be received
     * @param swapPath The encoded swap path to use for token swaps
     */
    function moveLiquidityForRewardWithPath(
        ITorex torex0,
        ITorex torex1,
        address rewardAddress,
        uint256 rewardAmountMinimum,
        bytes calldata swapPath
    )
        external
    {
        _moveLiquidity(torex0, torex1, rewardAddress, rewardAmountMinimum, swapPath);
    }

    /**
     * @notice Callback function for Torex LME
     * @param inToken The input token
     * @param outToken The output token
     * @param minOutAmount The minimum output amount specified
     * @param moverData The encoded context for the liquidity movement
     */
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
        // Decode the context for the liquidity movement
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

                // Prepare In and Out Tokens (unwrapping and converting SuperTokens to ERC20)
                (IERC20 swapInToken, uint256 swapInAmount) =
                    _prepareInTokenForSwap(inToken, inToken.balanceOf(address(this)));
                (SuperTokenType outTokenType, IERC20 swapOutToken, uint256 swapOutAmountMinimum) =
                    _prepareOutTokenForSwap(outToken, outToken.balanceOf(address(this)));

                // Give swap router maximum allowance if necessary.
                if (swapInToken.allowance(address(this), address(SWAP_ROUTER)) < swapInAmount) {
                    TransferHelper.safeApprove(address(swapInToken), address(SWAP_ROUTER), type(uint256).max);
                }

                if (ctx.richTorexSwapPath.length == 0) {
                    if (ctx.richTorexObserver.getTypeId() != keccak256("UniswapV3PoolTwapObserver")) {
                        revert INVALID_TWAP_OBSERVER();
                    }

                    ctx.richTorexSwapPath = abi.encodePacked(
                        address(swapInToken),
                        IUniswapV3PoolTwapObserver(address(ctx.richTorexObserver)).uniPool().fee(),
                        address(swapOutToken)
                    );
                }

                // Swap the inToken to outToken
                SWAP_ROUTER.exactInput(
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
            }

            // Transfer the leftover tokens to the reward address
            TransferHelper.safeTransfer(address(inToken), ctx.rewardAddress, inToken.balanceOf(address(this)));
            TransferHelper.safeTransfer(address(outToken), ctx.rewardAddress, outToken.balanceOf(address(this)));
        } else if (msg.sender == address(ctx.poorTorex)) {
            // Transfer the outToken amount to the Poor Torex
            TransferHelper.safeTransfer(address(outToken), msg.sender, minOutAmount);
        } else {
            revert SENDER_MUST_BE_TOREX();
        }
        return true;
    }

    //      ____      __                        __   ______                 __  _
    //     /  _/___  / /____  _________  ____ _/ /  / ____/_  ______  _____/ /_(_)___  ____  _____
    //     / // __ \/ __/ _ \/ ___/ __ \/ __ `/ /  / /_  / / / / __ \/ ___/ __/ / __ \/ __ \/ ___/
    //   _/ // / / / /_/  __/ /  / / / / /_/ / /  / __/ / /_/ / / / / /__/ /_/ / /_/ / / / (__  )
    //  /___/_/ /_/\__/\___/_/  /_/ /_/\__,_/_/  /_/    \__,_/_/ /_/\___/\__/_/\____/_/ /_/____/

    /**
     * @notice Initializes the context for the liquidity movement
     * @param richTorex The Rich Torex
     * @param poorTorex The Poor Torex
     * @param rewardAddress The address that will receive the rewards
     * @param rewardAmountMinimum The minimum reward amount that must be received
     * @param swapPath The encoded swap path for the rich Torex's tokens
     * @return ctx The initialized context
     */
    function _initializeContext(
        ITorex richTorex,
        ITorex poorTorex,
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
        TorexConfig memory poorTorexConfig = ctx.poorTorex.getConfig();

        if (richTorexConfig.inToken != poorTorexConfig.outToken || richTorexConfig.outToken != poorTorexConfig.inToken)
        {
            revert INVALID_TWIN_TOREX_PAIR();
        }

        ctx.richTorexObserver = ITwapObserver(address(richTorexConfig.observer));
    }

    /**
     * @notice Internal function to move liquidity between two Torexes
     * @param torex0 The first Torex
     * @param torex1 The second Torex
     * @param rewardAddress The address that will receive the rewards
     * @param rewardAmountMinimum The minimum reward amount that must be received
     * @param swapPath The encoded swap path for the rich Torex's tokens
     */
    function _moveLiquidity(
        ITorex torex0,
        ITorex torex1,
        address rewardAddress,
        uint256 rewardAmountMinimum,
        bytes memory swapPath
    )
        private
    {
        // Get the liquidity estimations for the both Torexes
        (uint256 t0InAmount, uint256 t0MinOutAmount,,) = torex0.getLiquidityEstimations();
        (uint256 t1InAmount, uint256 t1MinOutAmount,,) = torex1.getLiquidityEstimations();

        ITorex richTorex;
        ITorex poorTorex;

        // Define which Torex (RichTorex) can pay for its twin Torex (PoorTorex) LME.
        if (t0InAmount >= t1MinOutAmount) {
            richTorex = torex0;
            poorTorex = torex1;
        } else if (t1InAmount >= t0MinOutAmount) {
            richTorex = torex1;
            poorTorex = torex0;
        } else {
            revert INVALID_TWIN_TOREX_SETUP();
        }

        // Initialize the context for the liquidity movement
        Context memory ctx = _initializeContext(richTorex, poorTorex, rewardAddress, rewardAmountMinimum, swapPath);

        // Initiate LME for the Rich Torex
        richTorex.moveLiquidity(abi.encode(ctx));
    }

    /**
     * @notice Prepares the inToken for the swap
     * @param inToken The input token
     * @param inAmount The amount of input tokens
     * @return swapInToken The token to swap
     * @return swapInAmount The amount of input tokens to swap
     */
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

    /**
     * @notice Prepares the outToken for the swap
     * @param outToken The output token
     * @param outAmount The amount of output tokens
     * @return outTokenType The type of the output token
     * @return swapOutToken The token to swap
     * @return swapOutAmountMinimum The minimum amount of output tokens to receive
     */
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

    /**
     * @notice Upgrades all tokens to the outToken
     * @param swapOutToken The ERC20 token to upgrade
     * @param outToken The output SuperToken
     * @param outTokenType The SuperToken type of the output token
     * @param to The token recipient address
     * @return outTokenAmount The amount of outToken upgraded
     */
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

    /**
     * @notice Gets the SuperToken type and underlying token address
     * @param superToken The SuperToken to check
     * @return superTokenType The type of the SuperToken
     * @return underlyingTokenAddress The address of the underlying token
     */
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

    /**
     * @notice Rounds up the output amount
     * @param outAmount The amount of output tokens
     * @param underlyingTokenDecimals The decimals of the underlying token
     * @return outAmountAdjusted The adjusted output amount
     */
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

    /**
     * @notice Converts an underlying token amount to a SuperToken amount
     * @param underlyingAmount The amount of underlying tokens
     * @param underlyingDecimals The decimals of the underlying token
     * @return superTokenAmount The amount of SuperToken
     */
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
