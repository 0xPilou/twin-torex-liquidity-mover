// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { ILiquidityMover } from "./interfaces/superboring/ILiquidityMover.sol";
import { ITorex } from "./interfaces/superboring/ITorex.sol";
import { ISuperToken } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperToken.sol";

contract SingleTorexLiquidityMover is ILiquidityMover {
    address private transient _liquiditySource;
    address private transient _torex;

    error INVALID_INVOKER();

    function moveLiquidity(ITorex torex) external {
        _liquiditySource = msg.sender;
        _torex = address(torex);

        torex.moveLiquidity(bytes(""));
    }

    /// @inheritdoc ILiquidityMover
    function moveLiquidityCallback(
        ISuperToken inToken,
        ISuperToken outToken,
        uint256 inAmount,
        uint256 minOutAmount,
        bytes calldata
    )
        external
        returns (bool success)
    {
        if (msg.sender != _torex) revert INVALID_INVOKER();

        outToken.transferFrom(_liquiditySource, msg.sender, minOutAmount);
        inToken.transfer(_liquiditySource, inAmount);

        success = true;
    }
}
