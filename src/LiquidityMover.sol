// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.15; // TODO: Forced this because IWETH9 required 0.8.15.

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IUniswapV3Pool } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import { TransferHelper } from "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import { ISwapRouter } from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import { IWETH9 } from "@uniswap/v3-periphery/contracts/interfaces/external/IWETH9.sol";

import { AutomateReady } from "automate/integrations/AutomateReady.sol";

import { ISuperToken } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperToken.sol";
import { ISETHCustom, ISETH } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/tokens/ISETH.sol";

interface ILiquidityMover {
    function execute(ISuperToken inToken, ISuperToken outToken, uint256 inAmount, uint256 outAmount) external;
}

interface Torex {
    function getMinOutAmount(uint256 inAmount) external view returns (uint256);
    function getInToken() external view returns (ISuperToken);
    function getOutToken() external view returns (ISuperToken);
    function getUniswapV3Pool() external view returns (IUniswapV3Pool);

    function moveLiquidity(uint256 inAmount, uint256 outAmount) external;
}

contract UniswapLiquidityMover is AutomateReady, ILiquidityMover {
    ISwapRouter public immutable swapRouter;
    IWETH9 public immutable WETH; // TODO: This might change in time?
    // TODO: Specify Native Asset Super Token here?

    // For this example, we will set the pool fee to 0.3%.
    uint24 public constant poolFee = 3000; // TODO: Get this from TOREX's pool?

    // Define a struct to hold your key-value pairs
    struct OnlyDuringTransactionData {
        Torex torex;
        IERC20 inTokenNormalized;
        uint256 inAmountForSwap;
        uint256 inAmountUsedForSwap;
    }
    // TODO: use amounts without sign?

    // Define a state variable to store the data
    // Not a fan of "ephemeral". I'd prefer another name that signifies better "only during transaction data".
    OnlyDuringTransactionData private duringTransactionData;

    constructor(
        ISwapRouter _swapRouter,
        // TODO: decimals for WETH?
        IWETH9 _WETH,
        address _automate,
        address _taskCreator
    )
        AutomateReady(_automate, _taskCreator)
    {
        swapRouter = _swapRouter;
        WETH = _WETH;
    }

    // TODO: Pass in profit margin?
    // TODO: Pass in Uniswap v3 pool with fee?
    // TODO: lock for re-entrancy
    function moveLiquidity(Torex torex, address rewardAddress, uint256 minRewardAmount) public {
        ISuperToken inToken = torex.getInToken();

        uint256 maxInAmount = inToken.balanceOf(address(torex));
        uint256 minOutAmount = torex.getMinOutAmount(maxInAmount);

        duringTransactionData = OnlyDuringTransactionData({
            torex: torex,
            inTokenNormalized: IERC20(address(0)),
            inAmountForSwap: 0,
            inAmountUsedForSwap: 0
        });

        torex.moveLiquidity(maxInAmount, minOutAmount);

        uint256 reward = duringTransactionData.inAmountForSwap - duringTransactionData.inAmountUsedForSwap;
        require(reward >= minRewardAmount, "LiquidityMover: reward too low");

        duringTransactionData.inTokenNormalized.transfer(rewardAddress, reward);

        delete duringTransactionData;
    }

    // TODO: Implement the part where we pay Gelato and send rest to the reward receiver.
    // function moveLiquiditySelfPaying(Torex torex) external onlyDedicatedMsgSender {
    //     this.moveLiquidity(torex);

    //     // swap to USDC or ETH
    //     (uint256 fee, address feeToken) = _getFeeDetails();
    //     _transfer(fee, feeToken);
    // }

    function execute(
        ISuperToken inToken,
        ISuperToken outToken,
        // TODO: Rename or add comments? Alternative names could be `sentInAmount` and `minOutAmount`.
        uint256 inAmount,
        uint256 outAmount
    )
        // TODO: lock for re-entrancy
        external
        override
    {
        // The expectation is that TOREX calls this contract when liquidity movement is happening and transfers inTokens
        // here.

        Torex torex = duringTransactionData.torex;
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
            // TODO: is it correct to assume 18 decimals for native asset? No, not correct. Actually, it might be...
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
            outAmountForSwap = outAmount; // TODO: is it correct to assume 18 decimals for native asset?
        } else {
            // Pure Super Token
            outTokenForSwap = IERC20(outToken);
            outAmountForSwap = outAmount;
        }
        // ---

        // # Swap
        // TODO: This part could be decoupled into an abstract base class?
        // Single swap guide about Swap Router: https://docs.uniswap.org/contracts/v3/guides/swaps/single-swaps
        TransferHelper.safeApprove(
            address(inTokenForSwap), address(swapRouter), inTokenForSwap.balanceOf(address(this))
        );

        ISwapRouter.ExactOutputSingleParams memory params = ISwapRouter.ExactOutputSingleParams({
            tokenIn: address(inTokenForSwap),
            tokenOut: address(outTokenForSwap),
            fee: poolFee, // TODO: this should be passed in?
            recipient: address(this),
            deadline: block.timestamp,
            // decimals need to be handled here
            amountOut: outAmountForSwap, // can this amount always be wrapped to the expected out amount?
            amountInMaximum: inTokenForSwap.balanceOf(address(this)), // TODO: can this be slightly optimized?
            sqrtPriceLimitX96: 0
        });
        uint256 inAmountUsedForSwap = swapRouter.exactOutputSingle(params);

        // Reset allowance for in token (it's better to reset for tokens like USDT which rever when `approve` is called
        // but allowance is not 0)
        if (inAmountUsedForSwap < inAmountForSwap) {
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

        // # Pay Profit
        duringTransactionData = OnlyDuringTransactionData({
            torex: torex,
            inTokenNormalized: inTokenForSwap,
            inAmountForSwap: inAmountForSwap,
            inAmountUsedForSwap: inAmountUsedForSwap
        });
    }

    enum SuperTokenType {
        Pure,
        Wrapper,
        NativeAsset
    }

    function getSuperTokenType(ISuperToken superToken) private view returns (SuperTokenType, address) {
        // TODO: Allow for optimization from off-chain set-up?
        bool isNativeAssetSuperToken;
        (isNativeAssetSuperToken,) =
            address(superToken).staticcall(abi.encodeWithSelector(ISETHCustom.upgradeByETH.selector));
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
