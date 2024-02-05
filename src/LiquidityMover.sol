// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.15; // TODO: Forced this because IWETH9 required 0.8.15.

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IUniswapV3Pool } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import { TransferHelper } from "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import { ISwapRouter } from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import { IPeripheryImmutableState } from "@uniswap/v3-periphery/contracts/interfaces/IPeripheryImmutableState.sol";
import { IWETH9 } from "@uniswap/v3-periphery/contracts/interfaces/external/IWETH9.sol";

import { AutomateReady } from "automate/integrations/AutomateReady.sol";

import { ISuperToken } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperToken.sol";
import { ISETHCustom, ISETH } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/tokens/ISETH.sol";

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
        uint256 minOutAmount
    )
        external
        returns (bool);
}

// TorexCore.CoreConfig memory cc = torexArray[i].getCoreConfig();

struct CoreConfig {
    address host;
    ISuperToken inToken;
    ISuperToken outToken;
    // Scaling factor between inToken flowrate and units assigned in the GDA pool for outToken distribution.
    uint128 outTokenDistributionPoolScaler;
    // Discount model factor, see getDiscountModelFactor function.
    uint256 discountModelFactor;
    // Uniswap V3 Pool TWAP Oracle Configurations
    //
    /// The Uniswap V3 pool to be used as price benchmark for liquidity moving.
    IUniswapV3Pool uniV3Pool;
    /// Uniswap pool is bi-direction but torex is not. If false, inToken maps to token0, and vice versa.
    bool uniV3PoolInverseOrder;
    /// Scaler used for the quotes from the pool.
    // Scaler
    bool uniV3QuoteScaler;
}

interface Torex {
    // function inToken() external view returns (ISuperToken);
    // function outToken() external view returns (ISuperToken);
    // function uniV3Pool() external view returns (IUniswapV3Pool);
    function getBenchmarkQuote(uint256 inAmount) external view returns (uint256);
    function getCoreConfig() external view returns (CoreConfig memory);

    function moveLiquidity() external;
}

interface IUniswapSwapRouter is ISwapRouter, IPeripheryImmutableState { }

contract UniswapLiquidityMover is ILiquidityMover {
    // , AutomateReady
    ISwapRouter public immutable swapRouter;
    IWETH9 public immutable WETH; // TODO: This might change in time?
    ISETH public immutable SETH; // TODO: This might change in time?
        // TODO: Specify Native Asset Super Token here?

    // For this example, we will set the pool fee to 0.3%.
    // uint24 public constant poolFee = 3000; // TODO: Get this from TOREX's pool?

    // Define a struct to hold your key-value pairs
    struct TransientStorage {
        Torex torex;
        IERC20 inTokenNormalized;
        uint256 inAmountForSwap;
        uint256 inAmountUsedForSwap;
    }

    // Note that this storage should be emptied by the end of each transaction.
    // Named after: https://eips.ethereum.org/EIPS/eip-1153
    TransientStorage private transientStorage;

    constructor(
        IUniswapSwapRouter _swapRouter, // TODO: Technically this could be inherited from.
            // Uniswap addresses available here: https://docs.uniswap.org/contracts/v3/reference/deployments (e.g.
            // 0xE592427A0AEce92De3Edee1F18E0157C05861564 for swap router)
            // address _automate,
            // address _taskCreator
        ISETH _nativeAssetSuperToken
    ) {
        // AutomateReady(_automate, _taskCreator)
        swapRouter = _swapRouter;
        WETH = IWETH9(_swapRouter.WETH9());
        SETH = _nativeAssetSuperToken; // TODO: Get this from the protcol?
    }

    // TODO: Pass in profit margin?
    // TODO: Pass in Uniswap v3 pool with fee?
    // TODO: lock for re-entrancy
    function moveLiquidity(Torex torex, address rewardAddress, uint256 minRewardAmount) public returns (bool) {
        transientStorage = TransientStorage({
            torex: torex,
            inTokenNormalized: IERC20(address(0)),
            inAmountForSwap: 0,
            inAmountUsedForSwap: 0
        });

        torex.moveLiquidity();

        uint256 reward = transientStorage.inAmountForSwap - transientStorage.inAmountUsedForSwap;
        require(reward >= minRewardAmount, "LiquidityMover: reward too low");

        transientStorage.inTokenNormalized.transfer(rewardAddress, reward);

        delete transientStorage;

        return true;
    }

    // TODO: Implement the part where we pay Gelato and send rest to the reward receiver.
    // function moveLiquiditySelfPaying(Torex torex) external onlyDedicatedMsgSender {
    //     this.moveLiquidity(torex);

    //     // swap to USDC or ETH
    //     (uint256 fee, address feeToken) = _getFeeDetails();
    //     _transfer(fee, feeToken);
    // }

    function moveLiquidityCallback(
        ISuperToken inToken,
        ISuperToken outToken,
        // TODO: Rename or add comments? Alternative names could be `sentInAmount` and `minOutAmount`.
        uint256 inAmount,
        uint256 outAmount
    )
        // TODO: lock for re-entrancy
        external
        override
        returns (bool)
    {
        // The expectation is that TOREX calls this contract when liquidity movement is happening and transfers inTokens
        // here.

        Torex torex = transientStorage.torex;
        require(address(torex) == msg.sender, "LiquidityMover: expecting caller to be TOREX");

        // # Normalize In and Out Tokens
        // It means unwrapping and converting them to an ERC-20 that the swap router understands.
        (SuperTokenType inTokenType, address inTokenUnderlyingToken) = getSuperTokenType(inToken);
        IERC20 inTokenForSwap;
        uint256 inAmountForSwap;
        if (inTokenType == SuperTokenType.Wrapper) {
            inToken.downgrade(inAmount);
            inTokenForSwap = IERC20(inTokenUnderlyingToken);
            inAmountForSwap = inTokenForSwap.balanceOf(address(this));
            // We use `balanceOf` so we wouldn't need to check for decimals.
            // Even if there was a previous balance (in case someone sent to this contract),
            // then we'll just use all of it.
        } else if (inTokenType == SuperTokenType.NativeAsset) {
            ISETH(address(inToken)).downgradeToETH(inAmount);
            WETH.deposit{ value: inAmount }();
            inTokenForSwap = WETH;
            inAmountForSwap = inAmount;
            // Assuming 18 decimals for the native asset.
        } else {
            // Pure Super Token
            inTokenForSwap = IERC20(inToken);
            inAmountForSwap = inAmount;
        }

        (SuperTokenType outTokenType, address outTokenUnderlyingToken) = getSuperTokenType(outToken);
        IERC20 outTokenForSwap;
        uint256 outAmountForSwap;
        if (outTokenType == SuperTokenType.Wrapper) {
            outTokenForSwap = IERC20(outTokenUnderlyingToken);
            (outAmountForSwap,) = outToken.toUnderlyingAmount(outAmount);
        } else if (outTokenType == SuperTokenType.NativeAsset) {
            outTokenForSwap = WETH;
            outAmountForSwap = outAmount;
            // Assuming 18 decimals for the native asset.
        } else {
            // Pure Super Token
            outTokenForSwap = IERC20(outToken);
            outAmountForSwap = outAmount;
        }
        // ---

        // # Swap
        // TODO: This part could be decoupled into an abstract base class?
        // Single swap guide about Swap Router: https://docs.uniswap.org/contracts/v3/guides/swaps/single-swaps
        uint256 inTokenForSwapBalance = inTokenForSwap.balanceOf(address(this));
        TransferHelper.safeApprove(address(inTokenForSwap), address(swapRouter), inTokenForSwapBalance);

        ISwapRouter.ExactOutputSingleParams memory params = ISwapRouter.ExactOutputSingleParams({
            tokenIn: address(inTokenForSwap),
            tokenOut: address(outTokenForSwap),
            fee: torex.getCoreConfig().uniV3Pool.fee(),
            recipient: address(this),
            deadline: block.timestamp,
            amountOut: outAmountForSwap, // can this amount always be wrapped to the expected out amount?
            amountInMaximum: inTokenForSwapBalance,
            sqrtPriceLimitX96: 0
        });

        transientStorage = TransientStorage({
            torex: torex,
            inTokenNormalized: inTokenForSwap,
            inAmountForSwap: inAmountForSwap,
            inAmountUsedForSwap: swapRouter.exactOutputSingle(params)
        });

        // Reset allowance for in token (it's better to reset for tokens like USDT which rever when `approve` is called
        // but allowance is not 0)
        if (transientStorage.inAmountUsedForSwap < inAmountForSwap) {
            TransferHelper.safeApprove(address(inTokenForSwap), address(swapRouter), 0);
        }
        // ---

        // # Pay TOREX
        if (outTokenType == SuperTokenType.Wrapper) {
            // TODO: Is it possible that there could be some remnant allowance here that breaks USDT?
            TransferHelper.safeApprove(address(outTokenForSwap), address(outToken), outAmountForSwap);
            outToken.upgradeTo(address(torex), outAmount, new bytes(0));
            // Note that `upgradeTo` expects Super Token decimals.
        } else if (outTokenType == SuperTokenType.NativeAsset) {
            WETH.withdraw(outAmountForSwap);
            ISETH(address(outToken)).upgradeByETHTo(address(torex));
        } else {
            // Pure Super Token
            // `outToken` is same as `outTokenForSwap` in this case
            TransferHelper.safeTransfer(address(outToken), address(torex), outAmount);
        }
        // ---

        return true;
    }

    enum SuperTokenType {
        Pure,
        Wrapper,
        NativeAsset
    }

    function getSuperTokenType(ISuperToken superToken) private view returns (SuperTokenType, address) {
        // TODO: Allow for optimization from off-chain set-up?
        bool isNativeAssetSuperToken = address(superToken) == address(SETH);
        if (isNativeAssetSuperToken) {
            return (SuperTokenType.NativeAsset, address(0));
            // Note that there are a few exceptions where Native Asset Super Tokens have an underlying token,
            // but we don't want to use it, hence we don't return it.
        } else {
            address underlyingToken = superToken.getUnderlyingToken();
            if (underlyingToken != address(0)) {
                return (SuperTokenType.Wrapper, underlyingToken);
            } else {
                return (SuperTokenType.Pure, address(0));
            }
        }
    }
}
