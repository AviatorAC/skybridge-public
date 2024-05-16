// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { Test } from 'forge-std/Test.sol';
import { MockMessenger } from './MockMessenger.sol';

import { AviPredeploys } from "src/libraries/AviPredeploys.sol";

contract MessengerHolder is Test {
    MockMessenger internal l1Messenger;
    MockMessenger internal l2Messenger;

    constructor() {
        l1Messenger = MockMessenger(AviPredeploys.L1_CROSS_DOMAIN_MESSENGER);
        l2Messenger = MockMessenger(AviPredeploys.L2_CROSS_DOMAIN_MESSENGER);

        deployCodeTo(
            "MockMessenger.sol:MockMessenger",
            abi.encode(AviPredeploys.L2_CROSS_DOMAIN_MESSENGER, AviPredeploys.L2_STANDARD_BRIDGE),
            AviPredeploys.L1_CROSS_DOMAIN_MESSENGER
        );

        deployCodeTo(
            "MockMessenger.sol:MockMessenger",
            abi.encode(AviPredeploys.L1_CROSS_DOMAIN_MESSENGER, AviPredeploys.L1_STANDARD_BRIDGE),
            AviPredeploys.L2_CROSS_DOMAIN_MESSENGER
        );
    }

    modifier mockL1Messenger() {
        vm.startPrank(address(l1Messenger));

        _;

        vm.stopPrank();
    }

    modifier mockL2Messenger() {
        vm.startPrank(address(l2Messenger));

        _;

        vm.stopPrank();
    }

    modifier mockL1Bridge() {
        vm.startPrank(AviPredeploys.L1_STANDARD_BRIDGE);

        _;

        vm.stopPrank();
    }

    modifier mockL2Bridge() {
        vm.startPrank(AviPredeploys.L2_STANDARD_BRIDGE);

        _;

        vm.stopPrank();
    }

    function test() public virtual {}
}
