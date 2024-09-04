// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

// Inspired from https://github.dev/ethereum-optimism/optimism/blob/develop/packages/contracts-bedrock/test/setup/Bridge_Initializer.sol
import { SuperchainConfig } from "@eth-optimism/contracts-bedrock/src/L1/SuperchainConfig.sol";

import { CommonTest } from 'test/__setup__/CommonTest.sol';
import { MockOptimismPortal } from 'test/__setup__/OptimismPortal.sol';

contract OptimismStack is CommonTest {
    SuperchainConfig superchainConfig;
    address superchainConfigAddr;

    address superchainGuardian;

    MockOptimismPortal mockOptimismPortal;
    address mockOptimismPortalAddr;

    constructor() mockGod {
        superchainConfig = new SuperchainConfig{ salt: keccak256(bytes("salty")) }();
        superchainConfigAddr = address(superchainConfig);

        mockOptimismPortal = new MockOptimismPortal();
        mockOptimismPortalAddr = address(mockOptimismPortal);

        superchainGuardian = makeAddr("superchainGuardian");

        vm.store(
            address(superchainConfig),
            superchainConfig.GUARDIAN_SLOT(),
            bytes32(uint256(uint160(superchainGuardian)))
        );

        // Uncomment this if you encounter random issues. This is commented out because we cannot ignore setup files from coverages
        // require(superchainConfig.guardian() == superchainGuardian);
    }

    modifier mockGuardian() {
        vm.startPrank(superchainGuardian);

        _;

        vm.stopPrank();
    }

    function test() public override virtual {}
}
