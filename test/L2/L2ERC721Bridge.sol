// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { Predeploys } from "@eth-optimism/contracts-bedrock/src/libraries/Predeploys.sol";

import { CommonTest } from 'test/__setup__/CommonTest.sol';
import { MessengerHolder } from 'test/__setup__/MessengerHolder.sol';

import { L2AviERC721Bridge } from "src/L2/L2AviERC721Bridge.sol";
import { AviPredeploys } from "src/libraries/AviPredeploys.sol";

contract L2ERC721BridgeTest is CommonTest, MessengerHolder {
    L2AviERC721Bridge l2Bridge;

    constructor() mockGod {
        l2Bridge = new L2AviERC721Bridge(true);
        l2Bridge.initialize(AviPredeploys.L1_AVI_STANDARD_BRIDGE);
        l2Bridge.addBackend(address(god));
    }

    function test() public override(CommonTest, MessengerHolder) {}

    function test_RevertWhenTryingToDeployL2ERC721BridgeWithZeroAddress() public {
        l2Bridge = new L2AviERC721Bridge(true);
        vm.expectRevert("L2AviERC721Bridge: other bridge cannot be address(0)");
        l2Bridge.initialize(address(0));
    }

    function test_CreatingBridgeWithValidAddress() public {
        L2AviERC721Bridge bridge = new L2AviERC721Bridge(true);
        bridge.initialize(AviPredeploys.L1_AVI_STANDARD_BRIDGE);
        assertEq(address(bridge.OTHER_BRIDGE()), AviPredeploys.L1_AVI_STANDARD_BRIDGE);
    }

    function test_L2BridgeIsNeverPaused() public view {
        assertEq(l2Bridge.paused(), false);
    }

    function test_RevertWhenTryingToFinalizeBridgingERC721ToSelf() public mockGod {
        vm.expectRevert("L2AviERC721Bridge: local token cannot be self");

        l2Bridge.finalizeBridgeERC721(address(l2Bridge), nftL1, god, god, 1, "");
    }

    function test_RevertWhenTryingToFinalizeBridgingNonERC721() public mockGod {
        vm.expectRevert("L2AviERC721Bridge: local token interface is not compliant");

        l2Bridge.finalizeBridgeERC721(testTokenAddrL1, nftL1, god, god, 1, "");
    }

    function test_RevertWhenTryingToFinalizeBridgingWrongRemoteToken() public mockGod {
        vm.expectRevert("L2AviERC721Bridge: wrong remote token for Optimism Mintable ERC721 local token");

        l2Bridge.finalizeBridgeERC721(nftL1, nftL1, god, god, 1, "");
    }

    function test_RevertWhenTryingToFinalizeBridgingToZeroAddress() public mockGod {
        vm.expectRevert("L2AviERC721Bridge: cannot transfer to the zero address");

        l2Bridge.finalizeBridgeERC721(nftL1, nftL1, god, address(0), 1, "");
    }

    function test_FinalizeBridgeERC721() public mockGod {
        l2Bridge.finalizeBridgeERC721(nftL2, nftL1, god, god, 1, "");
    }

    function test_RevertWhenTryingToBridgeERC721WithNullRemoteToken() public mockGod {
        vm.deal(god, 1 ether);
        uint256 fee = l2Bridge.flatFee();

        vm.expectRevert("L2AviERC721Bridge: remote token cannot be address(0)");

        l2Bridge.bridgeERC721{ value: fee }(nftL2, address(0), 1, "");
    }

    function test_RevertWhenTryingToBridgeNFTThatCallerDoesNotOwn() public mockGod {
        nftL2Contract.safeMint(bob, 1);
        vm.deal(god, 1 ether);
        uint256 fee = l2Bridge.flatFee();

        vm.expectRevert("L2AviERC721Bridge: Withdrawal is not being initiated by NFT owner");

        l2Bridge.bridgeERC721{ value: fee }(nftL2, nftL1, 1, "");
    }

    function test_RevertWhenRemoteTokenDoesNotMatchLocalToken() public mockGod {
        nftL2Contract.safeMint(god, 1);
        vm.deal(god, 1 ether);
        uint256 fee = l2Bridge.flatFee();

        vm.expectRevert("L2AviERC721Bridge: remote token does not match given value");

        l2Bridge.bridgeERC721{ value: fee }(nftL2, nftL2, 1, "");
    }

    function test_BridgeERC721() public mockGod {
        nftL2Contract.safeMint(god, 1);
        vm.deal(god, 1 ether);

        l2Bridge.bridgeERC721{ value: l2Bridge.flatFee() }(nftL2, nftL1, 1, "");
    }
}
