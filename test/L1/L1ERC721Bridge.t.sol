// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { CommonTest } from 'test/__setup__/CommonTest.sol';
import { MessengerHolder } from 'test/__setup__/MessengerHolder.sol';
import { OptimismStack } from 'test/__setup__/OptimismStack.sol';
import { NoMoneyAllowed } from 'test/__setup__/NoMoneyAllowed.sol';

import { SuperchainConfig } from "@eth-optimism/contracts-bedrock/src/L1/SuperchainConfig.sol";

import { L1AviERC721Bridge } from "src/L1/L1AviERC721Bridge.sol";
import { AviERC721Bridge } from "src/universal/AviERC721Bridge.sol";

import "forge-std/console2.sol";

contract L1ERC721Bridge is CommonTest, OptimismStack {
    L1AviERC721Bridge l1Bridge;
    address otherBridge;
    NoMoneyAllowed noMoney;

    constructor() mockGod {
        l1Bridge = new L1AviERC721Bridge(payable(liquidityPool));

        otherBridge = makeAddr("otherBridge");

        testNFTL1.approve(address(l1Bridge), NFT_ID);

        noMoney = new NoMoneyAllowed();
    }

    modifier withEtchedSuperchainConfigAddress() {
        // If the slot changes again, uncomment this to find the new slot, and set the superchainConfig to point to some random address
        // for (uint i = 0; i < 20; i++) {
        //     console2.log("slot %d", i);
        //     console2.logBytes32(vm.load(address(l1Bridge), bytes32(abi.encodePacked(uint256(i)))));
        // }

        // Slot 3 stores the superchainConfig address
        vm.store(address(l1Bridge), bytes32(abi.encodePacked(uint256(4))), bytes32(uint256(uint160(superchainConfigAddr))));

        _;
    }

    function test() public override(CommonTest, OptimismStack) {}

    function test_ReturnsPaused() public withEtchedSuperchainConfigAddress{
        assertEq(l1Bridge.paused(), false);
    }

    function test_RevertsWhenNonOwnerTriesToSetOtherBridge() public {
        vm.expectRevert("AccessControl: account 0x7fa9385be102ac3eac297483dd6233d62b3e1496 is missing role 0x0000000000000000000000000000000000000000000000000000000000000000");

        l1Bridge.setOtherBridge(otherBridge);
    }

    function test_SetOtherBridge() public mockGod {
        l1Bridge.setOtherBridge(otherBridge);

        assertEq(l1Bridge.OTHER_BRIDGE(), otherBridge);
        assertEq(l1Bridge.otherBridge(), otherBridge);
    }

    function test_RevertWhenBridgeIsPaused() public withEtchedSuperchainConfigAddress {
        vm.prank(superchainGuardian);
        superchainConfig.pause("Checking revert when bridge is paused");

        assertEq(l1Bridge.paused(), true);

        vm.expectRevert("L1ERC721Bridge: paused");
        vm.prank(god);
        l1Bridge.finalizeBridgeERC721(testNFTAddrL1, testNFTAddrL2, address(0), address(0), NFT_ID, "");
    }

    function test_RevertWhenBridgeIsSelf() public withEtchedSuperchainConfigAddress mockGod {
        vm.expectRevert("L1ERC721Bridge: local token cannot be self");
        l1Bridge.finalizeBridgeERC721(address(l1Bridge), testNFTAddrL2, address(0), address(0), NFT_ID, "");
    }

    function test_RevertWhenTokenPairIsNotEscrowed() public withEtchedSuperchainConfigAddress mockGod {
        vm.expectRevert("L1ERC721Bridge: Token ID is not escrowed in the L1 Bridge");
        l1Bridge.finalizeBridgeERC721(testNFTAddrL1, testNFTAddrL2, address(0), address(0), NFT_ID, "");
    }

    function test_RevertWhenTryingToBridgeNFTAsContract() public withEtchedSuperchainConfigAddress {
        vm.expectRevert("ERC721Bridge: account is not externally owned");
        // Sure, try it with the NFT itself, why not!
        vm.prank(testNFTAddrL1);

        l1Bridge.bridgeERC721(testNFTAddrL1, testNFTAddrL2, NFT_ID, "");
    }

    function test_RevertWhenTryingToBridgeNFTWithNullRemoteToken() public withEtchedSuperchainConfigAddress mockGod {
        vm.expectRevert("L1ERC721Bridge: remote token cannot be address(0)");
        l1Bridge.bridgeERC721(testNFTAddrL1, address(0), NFT_ID, "");
    }

    function test_BridgeERC721() public withEtchedSuperchainConfigAddress mockGod {
        vm.deal(god, 0.002 ether);
        l1Bridge.bridgeERC721{ value: 0.002 ether }(testNFTAddrL1, testNFTAddrL2, NFT_ID, "");

        assertEq(l1Bridge.deposits(testNFTAddrL1, testNFTAddrL2, NFT_ID), true);
    }

    function test_FinalizeBridgeERC721() public withEtchedSuperchainConfigAddress mockGod {
        vm.deal(god, 0.002 ether);
        l1Bridge.bridgeERC721{ value: 0.002 ether }(testNFTAddrL1, testNFTAddrL2, NFT_ID, "");

        l1Bridge.finalizeBridgeERC721(testNFTAddrL1, testNFTAddrL2, god, god, NFT_ID, "");

        assertEq(l1Bridge.deposits(testNFTAddrL1, testNFTAddrL2, NFT_ID), false);
    }

    function test_RevertsWhenTryingToBridgeNFTToNullAddress() public withEtchedSuperchainConfigAddress mockGod {
        vm.expectRevert("ERC721Bridge: nft recipient cannot be address(0)");
        l1Bridge.bridgeERC721To(testNFTAddrL1, testNFTAddrL2, address(0), NFT_ID, "");
    }

    function test_BridgeERC721To() public withEtchedSuperchainConfigAddress mockGod {
        vm.deal(god, 0.002 ether);
        l1Bridge.bridgeERC721To{ value: 0.002 ether }(testNFTAddrL1, testNFTAddrL2, god, NFT_ID, "");

        assertEq(l1Bridge.deposits(testNFTAddrL1, testNFTAddrL2, NFT_ID), true);
    }

    function test_RevertWhenTryingToSetFlatFeeTooHigh() public mockGod {
        vm.expectRevert("AviBridge: _fee must be less than 0.005 ether");
        l1Bridge.setFlatFee(0.1 ether);
    }

    function test_SetFlatFee() public mockGod {
        l1Bridge.setFlatFee(0.001 ether);

        assertEq(l1Bridge.flatFee(), 0.001 ether);
    }

    function test_RevertWhenTryingToBridgeNFTWithWrongFee() public withEtchedSuperchainConfigAddress mockGod {
        vm.deal(god, 0.001 ether);
        l1Bridge.setFlatFee(0.002 ether);

        vm.expectRevert("L1ERC721Bridge: bridging ERC721 must include sufficient ETH value");
        l1Bridge.bridgeERC721{ value: 0.001 ether }(testNFTAddrL1, testNFTAddrL2, NFT_ID, "");
    }

    function test_RevertWhenFailingToBridgeDueToLiquidityPoolNotReceivingTheETHFee() public mockGod {
        L1AviERC721Bridge tempBridge = new L1AviERC721Bridge(payable(address(noMoney)));

        vm.store(address(tempBridge), bytes32(abi.encodePacked(uint256(3))), bytes32(uint256(uint160(superchainConfigAddr))));

        vm.deal(god, 0.002 ether);

        vm.expectRevert("L1ERC721Bridge: failed to send ETH to liquidity pool");
        tempBridge.bridgeERC721{ value: 0.002 ether }(testNFTAddrL1, testNFTAddrL2, NFT_ID, "");
    }
}
