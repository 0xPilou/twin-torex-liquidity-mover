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
    function execute(
        ISuperToken inToken,
        ISuperToken outToken,
        uint256 inAmount,
        uint256 outAmount
    )
        // bytes calldata ctx
        external;
}

interface Torex {
    function getMinOutAmount(uint256 inAmount) external view returns (uint256);
    function getInToken() external view returns (ISuperToken);
    function getOutToken() external view returns (ISuperToken);
    function getUniswapV3Pool() external view returns (IUniswapV3Pool);

    // , bytes calldata ctx
    function moveLiquidity(uint256 inAmount, uint256 outAmount) external;
}

contract UniswapLiquidityMover is AutomateReady, ILiquidityMover {
    ISwapRouter public immutable swapRouter;
    IWETH9 public immutable WETH; // TODO: This might change in time?

    // For this example, we will set the pool fee to 0.3%.
    uint24 public constant poolFee = 3000; // TODO: Get this from TOREX's pool?

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

    receive() external payable { }

    // TODO: Pass in profit margin?
    // TODO: Pass in reward receiver?
    // TODO: Pass in Uniswap v3 pool with fee?
    function moveLiquidity(Torex torex) public {
        ISuperToken inToken = torex.getInToken();

        uint256 maxInAmount = inToken.balanceOf(address(torex));
        uint256 minOutAmount = torex.getMinOutAmount(maxInAmount);

        // (1/2) TODO: Would like to store information here
        // e.g. profit margin

        torex.moveLiquidity(maxInAmount, minOutAmount);

        // (2/2) TODO: And retrieve it here, possibly with added data from `moveLiquidity`
        // use-case is to handle Gelato self-pay and send the profit to the user
        // Note that this function can still be used with Gelato's 1Balance.
    }

    // TODO: Implement the part where we pay Gelato and send rest to the reward receiver.
    function moveLiquiditySelfPaying(Torex torex) external onlyDedicatedMsgSender {
        this.moveLiquidity(torex);

        // swap to USDC or ETH
        (uint256 fee, address feeToken) = _getFeeDetails();
        _transfer(fee, feeToken);
    }

    function execute(
        ISuperToken inToken,
        ISuperToken outToken,
        // TODO: rename to `transferredInAmount` and `minOutAmount`
        uint256 inAmount,
        uint256 outAmount
    )
        // TODO: lock for re-entrancy
        external
        override
    {
        // The expectation is that TOREX calls this contract when liquidity movement is happening and transfers inTokens
        // here.

        // TODO: validate if TOREX
        // torex registry?
        Torex torex = Torex(msg.sender);

        // IUniswapV3Pool uniswapV3Pool = torex.getUniswapV3Pool(); // better to get in and out token from here?
        // Probably not, because I don't know the direction.

        // # Normalize In and Out Tokens
        // It means unwrapping and converting them to an ERC-20 that the swap router understands.
        SuperTokenType inTokenType = getSuperTokenType(inToken); // TODO: return 2 value (tuple)
        IERC20 inTokenNormalized;
        uint256 inAmountNormalized;
        if (inTokenType == SuperTokenType.Wrapper) {
            inToken.downgrade(inAmount);
            inTokenNormalized = IERC20(inToken.getUnderlyingToken());
            // TODO: consider if this is not from `inAmount`
            inAmountNormalized = inTokenNormalized.balanceOf(address(this));
        } else if (inTokenType == SuperTokenType.NativeAsset) {
            ISETH(address(inToken)).downgradeToETH(inAmount);
            WETH.deposit{ value: inAmount }();
            inTokenNormalized = WETH;
            inAmountNormalized = inAmount;
            // TODO: is it correct to assume 18 decimals for native asset? No, not correct.
        } else {
            // Pure Super Token
            inTokenNormalized = IERC20(inToken);
            inAmountNormalized = inAmount;
        }

        SuperTokenType outTokenType = getSuperTokenType(outToken);
        IERC20 outTokenNormalized;
        uint256 outAmountNormalized;
        if (outTokenType == SuperTokenType.Wrapper) {
            outTokenNormalized = IERC20(outToken.getUnderlyingToken());
            (outAmountNormalized,) = outToken.toUnderlyingAmount(outAmount);
        } else if (outTokenType == SuperTokenType.NativeAsset) {
            outTokenNormalized = WETH;
            outAmountNormalized = outAmount; // TODO: is it correct to assume 18 decimals for native asset?
        } else {
            // Pure Super Token
            outTokenNormalized = IERC20(outToken);
            outAmountNormalized = outAmount;
        }
        // ---

        // # Swap
        // TODO: This part could be decoupled into an abstract base class?
        // Single swap guide about Swap Router: https://docs.uniswap.org/contracts/v3/guides/swaps/single-swaps
        TransferHelper.safeApprove(
            address(inTokenNormalized), address(swapRouter), inTokenNormalized.balanceOf(address(this))
        );

        ISwapRouter.ExactOutputSingleParams memory params = ISwapRouter.ExactOutputSingleParams({
            tokenIn: address(inTokenNormalized),
            tokenOut: address(outTokenNormalized),
            fee: poolFee, // TODO: this should be passed in?
            recipient: address(this),
            deadline: block.timestamp,
            // decimals need to be handled here
            amountOut: outAmountNormalized, // can this amount always be wrapped to the expected out amount?
            amountInMaximum: inTokenNormalized.balanceOf(address(this)), // TODO: can this be slightly optimized?
            sqrtPriceLimitX96: 0
        });
        uint256 usedInAmount = swapRouter.exactOutputSingle(params);

        // Reset allowance for in token (it's better to reset for tokens like USDT which rever when `approve` is called
        // but allowance is not 0)
        if (usedInAmount < inAmountNormalized) {
            TransferHelper.safeApprove(address(inTokenNormalized), address(swapRouter), 0);
        }
        // ---

        // # Pay TOREX
        if (outTokenType == SuperTokenType.Wrapper) {
            // TODO: Is it possible that there could be some remnant allowance here that breaks USDT?
            TransferHelper.safeApprove(address(outTokenNormalized), address(outToken), outAmountNormalized);
            outToken.upgradeTo(address(torex), outAmount, new bytes(0));
            // Note that amount with Super Token decimals (i.e. `outAmount`) should be used here.
        } else if (outTokenType == SuperTokenType.NativeAsset) {
            WETH.withdraw(outAmountNormalized);
            ISETH(address(outToken)).upgradeByETHTo(address(torex));
        } else {
            // Pure Super Token
            // `outToken` is same as `outTokenNormalized` in this case
            TransferHelper.safeTransfer(address(outToken), address(torex), outAmount);
        }
        // ---

        // # Pay Profit
        // TODO: will depend on whether self-paying or not?

        // pass out inTokenNormalized
        // pass out inAmountNormalized
        // pass out usedInAmount
    }

    function getSuperTokenType(ISuperToken superToken) private view returns (SuperTokenType) {
        // TODO: Test if this works.
        // TODO: Allow for optimization from off-chain set-up
        (bool isNativeAssetSuperToken,) =
            address(superToken).staticcall(abi.encodeWithSelector(ISETHCustom.upgradeByETH.selector));
        if (isNativeAssetSuperToken) {
            return SuperTokenType.NativeAsset;
        } else {
            if (superToken.getUnderlyingToken() != address(0)) {
                // TODO: A few Native Asset Super Tokens have an underlying token?
                return SuperTokenType.Wrapper;
            } else {
                return SuperTokenType.Pure;
            }
        }
    }

    // Is there a difference whether this is nested or not?
    enum SuperTokenType {
        Pure,
        Wrapper,
        NativeAsset
    }

    // EXPERIMENTATION below

    // Define a struct to hold your key-value pairs
    struct Data {
        IERC20 inTokenNormalized;
        // use without uint?
        uint256 inAmountNormalized;
        uint256 usedInAmount;
    }

    // Define a mapping to store the data associated with each address
    mapping(address => Data) public dataStore;

    function storeData(Data memory data) public {
        // Store the data in the mapping
        dataStore[msg.sender] = data;
    }

    function retrieveData() public view returns (Data memory) {
        // Retrieve the data from the mapping
        return dataStore[msg.sender];
    }

    function deleteData() public {
        // Delete the data from the mapping
        delete dataStore[msg.sender];
    }
}
