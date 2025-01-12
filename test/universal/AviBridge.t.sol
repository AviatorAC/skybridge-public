// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { CommonTest } from 'test/__setup__/CommonTest.sol';
import { MessengerHolder } from 'test/__setup__/MessengerHolder.sol';
import { NoMoneyAllowed } from 'test/__setup__/NoMoneyAllowed.sol';

import { AviBridge } from "src/universal/AviBridge.sol";
import { AviPredeploys } from "src/libraries/AviPredeploys.sol";

import "forge-std/console2.sol";
import { IOptimismMintableERC20, ILegacyMintableERC20 } from "@eth-optimism/contracts-bedrock/src/universal/IOptimismMintableERC20.sol";
import { ERC165Checker } from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";

contract RawBridge is AviBridge {
    function initialize(address payable messenger, address payable otherBridge) public initializer {
        __SkyBridge_init(messenger, otherBridge);
    }

    receive() external payable virtual override {}
}

contract AviBridgeTest is CommonTest, MessengerHolder {
    RawBridge bridge;
    NoMoneyAllowed noMoneyAllowed;

    constructor() mockGod {
        bridge = new RawBridge();
        bridge.initialize(payable(AviPredeploys.L1_CROSS_DOMAIN_MESSENGER), payable(address(AviPredeploys.L2_STANDARD_BRIDGE)));
        bridge.setPaused(false);
        noMoneyAllowed = new NoMoneyAllowed();
    }

    function test() public override(CommonTest, MessengerHolder) {}

    function test_RevertWhenNonAdminTriesToAddAdmin() public {
        vm.prank(bob);

        vm.expectRevert("AccessControl: account 0x1d96f2f6bef1202e4ce1ff6dad0c2cb002861d3e is missing role 0x0000000000000000000000000000000000000000000000000000000000000000");
        bridge.addAdmin(alice);
    }

    function test_AdminCanAddAdmin() public mockGod {
        bridge.addAdmin(alice);
    }

    function test_RevertWhenTryingToAddAdminTwice() public mockGod {
        bridge.addAdmin(alice);

        vm.expectRevert("Admin already added.");
        bridge.addAdmin(alice);
    }

    function test_RevertWhenNonAdminTriesToRemoveAdmin() public {
        vm.prank(bob);

        vm.expectRevert("AccessControl: account 0x1d96f2f6bef1202e4ce1ff6dad0c2cb002861d3e is missing role 0x0000000000000000000000000000000000000000000000000000000000000000");
        bridge.removeAdmin(alice);
    }

    function test_AdminCanRemoveAdmin() public mockGod {
        bridge.addAdmin(alice);
        bridge.removeAdmin(alice);
    }

    function test_RevertWhenAdminTriesToRemoveNonAdmin() public mockGod {
        vm.expectRevert("Address is not a recognized admin.");
        bridge.removeAdmin(alice);
    }

    function test_RevertWhenTryingToRemoveOnlyAdmin() public mockGod {
        vm.expectRevert("Cannot remove the only admin.");
        bridge.removeAdmin(god);
    }

    function test_MessengerGetterReturnsMessenger() public {
        assertEq(address(bridge.MESSENGER()), address(AviPredeploys.L1_CROSS_DOMAIN_MESSENGER));
    }

    function test_OtherBridgeGetterReturnsOtherBridge() public {
        assertEq(address(bridge.OTHER_BRIDGE()), AviPredeploys.L2_STANDARD_BRIDGE);
    }

    function test_PausedReturnsFalse() public {
        assertEq(bridge.paused(), false);
    }

    function test_RevertWhenTryingToFinalizeBridgeETHWhenPaused() public {
        vm.prank(god);
        bridge.setPaused(true);

        vm.prank(AviPredeploys.L1_CROSS_DOMAIN_MESSENGER);

        vm.expectRevert("AviBridge: paused");
        bridge.finalizeBridgeETH(god, god, 1 ether, "");
    }

    function test_RevertWhenTryingToFinalizeBridgeETHWithMismatchingValue() public mockL1Messenger {
        vm.deal(AviPredeploys.L1_CROSS_DOMAIN_MESSENGER, 1 ether);

        vm.expectRevert("AviBridge: amount sent does not match amount required");
        bridge.finalizeBridgeETH{ value: 0.5 ether }(god, god, 1 ether, "");
    }

    function test_RevertWhenTryingToFinalizeBridgeETHToSelf() public mockL1Messenger {
        vm.deal(AviPredeploys.L1_CROSS_DOMAIN_MESSENGER, 1 ether);

        vm.expectRevert("AviBridge: cannot send to self");
        bridge.finalizeBridgeETH{ value: 1 ether }(god, address(bridge), 1 ether, "");
    }

    function test_RevertWhenTryingToFinalizeBridgeETHToMessenger() public mockL1Messenger {
        vm.deal(AviPredeploys.L1_CROSS_DOMAIN_MESSENGER, 1 ether);

        vm.expectRevert("AviBridge: cannot send to messenger");
        bridge.finalizeBridgeETH{ value: 1 ether }(god, AviPredeploys.L1_CROSS_DOMAIN_MESSENGER, 1 ether, "");
    }

    function test_RevertWhenTryingToFinalizeBridgeETHFails() public mockL1Messenger {
        vm.deal(AviPredeploys.L1_CROSS_DOMAIN_MESSENGER, 1 ether);

        vm.expectRevert("AviBridge: ETH transfer failed");
        bridge.finalizeBridgeETH{ value: 1 ether }(god, address(noMoneyAllowed), 1 ether, "");
    }

    function test_RevertWhenTryingToFinalizeBridgeERC20WhenPaused() public {
        vm.prank(god);
        bridge.setPaused(true);

        vm.prank(AviPredeploys.L1_CROSS_DOMAIN_MESSENGER);

        vm.expectRevert("AviBridge: paused");
        bridge.finalizeBridgeERC20(testTokenAddrL1, testTokenAddrL2, god, god, 1, "");
    }

    function test_RevertWhenTryingToFinalizeBridgeERC20WithWrongRemoteTokenForLegacyLocalToken() public mockL1Messenger {
        vm.deal(AviPredeploys.L1_CROSS_DOMAIN_MESSENGER, 1 ether);

        vm.expectRevert("AviBridge: wrong remote token for Optimism Mintable ERC20 local token");
        bridge.finalizeBridgeERC20(legacyL1, testTokenAddrL2, god, god, 1, "");
    }

    function test_RevertWhenTryingToFinalizeBridgeERC20WithSameRemoteTokenForLegacyLocalToken() public mockL1Messenger {
        vm.deal(AviPredeploys.L1_CROSS_DOMAIN_MESSENGER, 1 ether);

        vm.expectRevert("AviBridge: wrong remote token for Optimism Mintable ERC20 local token");
        bridge.finalizeBridgeERC20(legacyL1, legacyL1, god, god, 1, "");
    }

    function test_RevertWhenTryingToFinalizeBridgeERC20WithSameRemoteTokenForModernLocalToken() public mockL1Messenger {
        vm.deal(AviPredeploys.L1_CROSS_DOMAIN_MESSENGER, 1 ether);

        vm.expectRevert("AviBridge: wrong remote token for Optimism Mintable ERC20 local token");
        bridge.finalizeBridgeERC20(newL1, newL1, god, god, 1, "");
    }

    function test_RevertWhenTryingToFinalizeBridgeERC20WithWrongRemoteTokenForModernLocalToken() public mockL1Messenger {
        vm.deal(AviPredeploys.L1_CROSS_DOMAIN_MESSENGER, 1 ether);

        vm.expectRevert("AviBridge: wrong remote token for Optimism Mintable ERC20 local token");
        bridge.finalizeBridgeERC20(newL1, testTokenAddrL2, god, god, 1, "");
    }

    function test_RevertWhenTryingToFinalizeBridgeERC20WithLegacyRemoteTokenForModernLocalToken() public mockL1Messenger {
        vm.deal(AviPredeploys.L1_CROSS_DOMAIN_MESSENGER, 1 ether);

        vm.expectRevert("AviBridge: wrong remote token for Optimism Mintable ERC20 local token");
        bridge.finalizeBridgeERC20(newL1, legacyL2, god, god, 1, "");
    }

    function test_RevertWhenTryingToFinalizeBridgeERC20WithModernRemoteTokenForLegacyLocalToken() public mockL1Messenger {
        vm.deal(AviPredeploys.L1_CROSS_DOMAIN_MESSENGER, 1 ether);

        vm.expectRevert("AviBridge: wrong remote token for Optimism Mintable ERC20 local token");
        bridge.finalizeBridgeERC20(legacyL1, newL2, god, god, 1, "");
    }

    function test_RevertWhenTryingToFinalizeBridgeERC20WithNotEnoughDepositedTokens() public mockL1Messenger {
        vm.expectRevert("AviBridge: insufficient balance deposited");
        bridge.finalizeBridgeERC20(testTokenAddrL1, testTokenAddrL2, god, god, 1, "");
    }
}
