// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {SuperfluidFrameworkDeployer} from
    "@superfluid-finance/ethereum-contracts/contracts/utils/SuperfluidFrameworkDeployer.t.sol";
import {ERC1820RegistryCompiled} from
    "@superfluid-finance/ethereum-contracts/contracts/libs/ERC1820RegistryCompiled.sol";
import {ISuperToken} from "@superfluid-finance/ethereum-contracts/contracts/superfluid/SuperToken.sol";

contract LiquidityMoverTest is Test {
    SuperfluidFrameworkDeployer.Framework internal _sf;
    SuperfluidFrameworkDeployer internal _deployer;

    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 ether;

    address public alice;
    address public bob;
    address public karen;
    address public treasury;

    ISuperToken internal _tokenA;
    ISuperToken internal _tokenB;
    ISuperToken internal _tokenC;
    ISuperToken internal _tokenD;

    function setUp() public virtual {
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        karen = makeAddr("karen");
        treasury = makeAddr("treasury");

        // Superfluid Protocol Deployment Start
        vm.etch(ERC1820RegistryCompiled.at, ERC1820RegistryCompiled.bin);

        _deployer = new SuperfluidFrameworkDeployer();
        _deployer.deployTestFramework();
        _sf = _deployer.getFramework();

        vm.startPrank(treasury);
        _tokenA = _deployer.deployPureSuperToken("TokenA", "tA", INITIAL_SUPPLY);
        _tokenB = _deployer.deployPureSuperToken("TokenB", "tB", INITIAL_SUPPLY);
        _tokenC = _deployer.deployPureSuperToken("TokenC", "tC", INITIAL_SUPPLY);
        _tokenD = _deployer.deployPureSuperToken("TokenD", "tD", INITIAL_SUPPLY);
        vm.stopPrank();
    }
}
