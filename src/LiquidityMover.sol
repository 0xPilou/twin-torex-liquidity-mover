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
        IERC20 inTokenForSwap;
        uint256 inAmountForSwap;
        uint256 inAmountUsedForSwap;
        IERC20 outTokenForSwap;
        uint256 outAmountForSwap;
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
        SETH = _nativeAssetSuperToken; // TODO: Get this from the protocol?
    }

    // TODO: Pass in profit margin?
    // TODO: Pass in Uniswap v3 pool with fee?
    // TODO: lock for re-entrancy
    function moveLiquidity(Torex torex, address rewardAddress, uint256 minRewardAmount) public returns (bool) {
        transientStorage.torex = torex;

        torex.moveLiquidity();

        uint256 reward = transientStorage.inAmountForSwap - transientStorage.inAmountUsedForSwap;
        require(reward >= minRewardAmount, "LiquidityMover: reward too low");

        transientStorage.inTokenForSwap.transfer(rewardAddress, reward);

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
        TransientStorage memory store = transientStorage;

        // The expectation is that TOREX calls this contract when liquidity movement is happening and transfers inTokens
        // here.
        require(
            address(store.torex) != address(0),
            "LiquidityMover: `moveLiquidityCallback` executed without calling the main function first"
        );
        require(address(store.torex) == msg.sender, "LiquidityMover: expecting caller to be TOREX");

        // # Normalize In and Out Tokens
        // It means unwrapping and converting them to an ERC-20 that the swap router understands.
        (SuperTokenType inTokenType, address inTokenUnderlyingToken) = getSuperTokenType(inToken);
        if (inTokenType == SuperTokenType.Wrapper) {
            inToken.downgrade(inAmount);
            store.inTokenForSwap = IERC20(inTokenUnderlyingToken);
        } else if (inTokenType == SuperTokenType.NativeAsset) {
            ISETH(address(inToken)).downgradeToETH(inAmount);
            WETH.deposit{ value: inAmount }();
            store.inTokenForSwap = WETH;
        } else {
            // Pure Super Token
            store.inTokenForSwap = IERC20(inToken);
        }

        // We use `balanceOf` so we wouldn't need to check for decimals.
        // Even if there was a previous balance (in case someone sent to this contract),
        // then we'll just use all of it.
        store.inAmountForSwap = store.inTokenForSwap.balanceOf(address(this));

        (SuperTokenType outTokenType, address outTokenUnderlyingToken) = getSuperTokenType(outToken);
        if (outTokenType == SuperTokenType.Wrapper) {
            store.outTokenForSwap = IERC20(outTokenUnderlyingToken);
            (store.outAmountForSwap,) = outToken.toUnderlyingAmount(outAmount);
        } else if (outTokenType == SuperTokenType.NativeAsset) {
            store.outTokenForSwap = WETH;
            store.outAmountForSwap = outAmount;
            // Assuming 18 decimals for the native asset.
        } else {
            // Pure Super Token
            store.outTokenForSwap = IERC20(outToken);
            store.outAmountForSwap = outAmount;
        }
        // ---

        // # Swap
        // TODO: This part could be decoupled into an abstract base class?
        // Single swap guide about Swap Router: https://docs.uniswap.org/contracts/v3/guides/swaps/single-swaps
        TransferHelper.safeApprove(address(store.inTokenForSwap), address(swapRouter), store.inAmountForSwap);

        ISwapRouter.ExactOutputSingleParams memory params = ISwapRouter.ExactOutputSingleParams({
            tokenIn: address(store.inTokenForSwap),
            tokenOut: address(store.outTokenForSwap),
            fee: store.torex.getCoreConfig().uniV3Pool.fee(),
            recipient: address(this),
            deadline: block.timestamp,
            amountOut: store.outAmountForSwap,
            amountInMaximum: store.inAmountForSwap,
            sqrtPriceLimitX96: 0
        });

        store.inAmountUsedForSwap = swapRouter.exactOutputSingle(params);

        // Reset allowance for in token (it's better to reset for tokens like USDT which rever when `approve` is called
        // but allowance is not 0)
        if (store.inAmountUsedForSwap < store.inAmountForSwap) {
            TransferHelper.safeApprove(address(store.inTokenForSwap), address(swapRouter), 0);
        }
        // ---

        // # Pay TOREX
        if (outTokenType == SuperTokenType.Wrapper) {
            // TODO: Is it possible that there could be some remnant allowance here that breaks USDT?
            TransferHelper.safeApprove(address(store.outTokenForSwap), address(outToken), store.outAmountForSwap);
            outToken.upgradeTo(address(store.torex), outAmount, new bytes(0));
            // Note that `upgradeTo` expects Super Token decimals.
        } else if (outTokenType == SuperTokenType.NativeAsset) {
            WETH.withdraw(store.outAmountForSwap);
            ISETH(address(outToken)).upgradeByETHTo(address(store.torex));
        } else {
            // Pure Super Token
            TransferHelper.safeTransfer(address(outToken), address(store.torex), outAmount);
        }
        // ---

        transientStorage = store;

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
