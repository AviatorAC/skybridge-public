// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { CommonTest } from 'test/__setup__/CommonTest.sol';

import { SkyBridgeERC20Factory } from "src/factories/SkyBridgeERC20Factory.sol";
import { SkyBridgeERC20 } from "src/factories/SkyBridgeERC20.sol";

contract SkyBridgeERC20FactoryTest is CommonTest {
	SkyBridgeERC20Factory factory;

	constructor() mockGod {
		address bridge = makeAddr("bridge");
		factory = new SkyBridgeERC20Factory(true);
		factory.initialize(bridge, address(god));
	}

	function test_CreatesTokenSuccessfully() public mockGod {
		vm.deal(god, 1 ether);

		address remoteToken = makeAddr("remote token");

		address newToken = factory.createSkyBridgeERC20{value: factory.flatFee()}(remoteToken, "TestToken", "OWO", 18);

		SkyBridgeERC20 token = SkyBridgeERC20(newToken);

		assertEq(token.REMOTE_TOKEN(), remoteToken);
	}

	function test_RevertsIfNonFactoryTriesToInitialize() public mockGod {
		vm.deal(god, 1 ether);

		SkyBridgeERC20 token = new SkyBridgeERC20(makeAddr("bridge"), address(factory));

		vm.expectRevert("SkyBridgeERC20: Only the factory can call this function");

		token.initialize(makeAddr("remote token"), "TestToken", "OWO", 18);
	}

	function test_CannotInitializeTwice() public {
		vm.prank(god);
		vm.deal(god, 1 ether);

		address remoteToken = makeAddr("remote token");

		address newToken = factory.createSkyBridgeERC20{value: factory.flatFee()}(remoteToken, "TestToken", "OWO", 18);

		SkyBridgeERC20 token = SkyBridgeERC20(newToken);

		vm.prank(address(factory));

		vm.expectRevert("Initializable: contract is already initialized");

		token.initialize(makeAddr("remote token"), "TestToken", "OWO", 18);
	}

	function test_TryingToCreateTokenTwiceFails() public mockGod {
		vm.deal(god, 1 ether);

		address remoteToken = makeAddr("remote token");
		uint256 fee = factory.flatFee();

		factory.createSkyBridgeERC20{value: fee}(remoteToken, "TestToken", "OWO", 18);

		vm.expectRevert();
		factory.createSkyBridgeERC20{value: fee}(remoteToken, "TestToken", "OWO", 18);
	}
}
