// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { CommonTest } from 'test/__setup__/CommonTest.sol';

import { SkyBridgeERC721Factory } from "src/factories/SkyBridgeERC721Factory.sol";
import { SkyBridgeERC721 } from "src/factories/SkyBridgeERC721.sol";

contract SkyBridgeERC721FactoryTest is CommonTest {
	SkyBridgeERC721Factory factory;

	constructor() mockGod {
		address bridge = makeAddr("bridge");
		factory = new SkyBridgeERC721Factory(true);
		factory.initialize(bridge, address(god), 420);
	}

	function test_CreatesTokenSuccessfully() public mockGod {
		vm.deal(god, 1 ether);

		address remoteToken = makeAddr("remote token");

		address newToken = factory.createSkyBridgeERC721{value: factory.flatFee()}(remoteToken, "TestNFT", "OWO");

		SkyBridgeERC721 token = SkyBridgeERC721(newToken);

		assertEq(token.REMOTE_TOKEN(), remoteToken);
	}

	function test_RevertsIfNonFactoryTriesToInitialize() public mockGod {
		vm.deal(god, 1 ether);

		SkyBridgeERC721 token = new SkyBridgeERC721(makeAddr("bridge"), address(factory));

		vm.expectRevert("SkyBridgeERC721: Only the factory can call this function");

		token.initialize(420, makeAddr("remote token"), "TestToken", "OWO");
	}

	function test_CannotInitializeTwice() public {
		vm.prank(god);
		vm.deal(god, 1 ether);

		address remoteToken = makeAddr("remote token");

		address newToken = factory.createSkyBridgeERC721{value: factory.flatFee()}(remoteToken, "TestToken", "OWO");

		SkyBridgeERC721 token = SkyBridgeERC721(newToken);

		vm.prank(address(factory));

		vm.expectRevert("Initializable: contract is already initialized");

		token.initialize(420, makeAddr("remote token"), "TestToken", "OWO");
	}

	function test_TryingToCreateTokenTwiceFails() public mockGod {
		vm.deal(god, 1 ether);

		address remoteToken = makeAddr("remote token");
		uint256 fee = factory.flatFee();

		factory.createSkyBridgeERC721{value: fee}(remoteToken, "TestToken", "OWO");

		vm.expectRevert();
		factory.createSkyBridgeERC721{value: fee}(remoteToken, "TestToken", "OWO");
	}
}
