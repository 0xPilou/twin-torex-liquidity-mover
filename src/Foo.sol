// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.21;

import { AutomateReady } from "automate/integrations/AutomateReady.sol";

contract LiquidityMover is AutomateReady {
    function id(uint256 value) external pure returns (uint256) {
        return value;
    }
}
