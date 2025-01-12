// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { CommonTest } from 'test/__setup__/CommonTest.sol';
import { MessengerHolder } from 'test/__setup__/MessengerHolder.sol';
import { NoMoneyAllowed } from 'test/__setup__/NoMoneyAllowed.sol';
import { OptimismStack } from 'test/__setup__/OptimismStack.sol';

import { L1AviBridge } from "src/L1/L1AviBridge.sol";
import { AviPredeploys } from "src/libraries/AviPredeploys.sol";

import "forge-std/console2.sol";

contract L1Bridge is CommonTest, MessengerHolder, OptimismStack {
    L1AviBridge l1Bridge;
    address otherBridgeTest;
    address l2Receiver;

    NoMoneyAllowed noMoneyAllowed;

    constructor() mockGod {
        l1Bridge = new L1AviBridge(true);
        l1Bridge.initialize(payable(address(l1Messenger)), payable(mockOptimismPortalAddr), payable(liquidityPool), testTokenAddrL1);

        l1Bridge.setBackend(god);

        l1Bridge.setPaused(false);

        // Make the bridge an admin of the liquidity pool
        liquidityPool.addAdmin(address(l1Bridge));

        otherBridgeTest = makeAddr("otherBridgeTest");
        l2Receiver = makeAddr("l2Receiver");

        noMoneyAllowed = new NoMoneyAllowed();
    }

    function test() public override(CommonTest, MessengerHolder, OptimismStack) {}

    function test_ChangingFlatFeeAsAdmin() public mockGod {
        l1Bridge.setFlatFee(100);

        assertEq(l1Bridge.flatFee(), 100);
    }

    function test_ChangingFlatFeeRecipientAsAdmin() public mockGod {
        l1Bridge.setFlatFeeRecipient(bob);

        assertEq(l1Bridge.flatFeeRecipient(), bob);
    }

    function test_RevertWhenTryingToSetFlatFeeTooHigh() public mockGod {
        vm.expectRevert("AviBridge: _fee must be less than or equal to 0.005 ether");

        l1Bridge.setFlatFee(500 ether);
    }

    function test_RevertWhenChangingFlatFeeAsNonAdmin() public {
        vm.prank(bob);
        vm.expectRevert("AccessControl: account 0x1d96f2f6bef1202e4ce1ff6dad0c2cb002861d3e is missing role 0x0000000000000000000000000000000000000000000000000000000000000000");

        l1Bridge.setFlatFee(100);
    }

    function test_ChangingBridgingFeeAsAdmin() public mockGod {
        l1Bridge.setBridgingFee(100);

        assertEq(l1Bridge.bridgingFee(), 100);
    }

    function test_RevertWhenChangingBridgingFeeAsNonAdmin() public {
        vm.prank(bob);
        vm.expectRevert("AccessControl: account 0x1d96f2f6bef1202e4ce1ff6dad0c2cb002861d3e is missing role 0x0000000000000000000000000000000000000000000000000000000000000000");

        l1Bridge.setBridgingFee(100);
    }

    function test_RevertWhenTryingToSetBridgingFeeTooHigh() public mockGod {
        vm.expectRevert("AviBridge: _fee must be less than or equal to 100");

        l1Bridge.setBridgingFee(1000);
    }

    function test_ChangingPausedAsAdmin() public mockGod {
        l1Bridge.setPaused(true);

        assertEq(l1Bridge.paused(), true);
    }

    function test_RevertWhenChangingPausedAsNonAdmin() public {
        vm.prank(bob);
        vm.expectRevert("AviBridge: function can only be called by pauser or admin role");

        l1Bridge.setPaused(true);
    }

    function test_RevertWhenChangingOtherBridgeAsNonAdmin() public {
        vm.prank(bob);
        vm.expectRevert("AccessControl: account 0x1d96f2f6bef1202e4ce1ff6dad0c2cb002861d3e is missing role 0x0000000000000000000000000000000000000000000000000000000000000000");

        l1Bridge.setOtherBridge(otherBridgeTest);
    }

    function test_ChangingOtherBridgeAsAdmin() public mockGod {
        l1Bridge.setOtherBridge(otherBridgeTest);

        assertEq(address(l1Bridge.OTHER_BRIDGE()), otherBridgeTest);
    }

    event ETHWithdrawalFinalized(address indexed from, address indexed to, uint256 amount, bytes extraData);

    event ERC20WithdrawalFinalized(
        address indexed l1Token,
        address indexed l2Token,
        address indexed from,
        address to,
        uint256 amount,
        bytes extraData
    );

    event ERC20BridgeFinalized(
        address indexed localToken,
        address indexed remoteToken,
        address indexed from,
        address to,
        uint256 amount,
        bytes extraData
    );

    function test_RevertWhenBridgeReceivesETHFromContract() public {
        vm.prank(address(liquidityPool));
        vm.expectRevert("AviBridge: function can only be called from an EOA");

        payable(address(l1Bridge)).transfer(1000 ether);
    }

    function test_RevertWhenBridgeReceivesETHWithNotEnoughValue() public mockGod {
        l1Bridge.setBridgingFee(25);
        l1Bridge.setFlatFee(0.005 ether);
        vm.deal(god, 0.1 ether);

        vm.expectRevert("AviBridge: insufficient ETH value");

        payable(address(l1Bridge)).call{ value: 0.0001 ether }("");
    }

    event ETHDepositInitiated(address indexed from, address indexed to, uint256 amount, bytes extraData);
    event ETHBridgeInitiated(address indexed from, address indexed to, uint256 amount, bytes extraData);

    function test_BridgeReceivesETH() public mockGod {
        l1Bridge.setBridgingFee(3);
        l1Bridge.setFlatFee(0.001 ether);
        vm.deal(god, 1 ether);

        vm.expectEmit(true, true, false, true);
        emit ETHDepositInitiated(god, god, 0.996003 ether, "");
        vm.expectEmit(true, true, false, true);
        emit ETHBridgeInitiated(god, god, 0.996003 ether, "");

        (bool success, ) = payable(l1Bridge).call{ value: 1 ether }("");
        assertTrue(success);
    }

    function test_RevertWhenTryingToBridgeETHOnL2WithNotEnoughValue() public mockGod {
        l1Bridge.setBridgingFee(25);
        l1Bridge.setFlatFee(0.001 ether);
        vm.deal(god, 0.01 ether);

        vm.expectRevert("AviBridge: insufficient ETH value");

        l1Bridge.bridgeETH{ value: 0.0001 ether }(0, "");
    }

    function test_BridgeDepositsETHOnL2() public mockGod {
        l1Bridge.setBridgingFee(3);
        l1Bridge.setFlatFee(0.001 ether);
        vm.deal(god, 1 ether);

        vm.expectEmit(true, true, false, true);
        emit ETHDepositInitiated(god, god, 0.996003 ether, "");
        vm.expectEmit(true, true, false, true);
        emit ETHBridgeInitiated(god, god, 0.996003 ether, "");

        l1Bridge.bridgeETH{ value: 1 ether }(0, "");
    }

    function test_RevertWhenTryingToBridgeETHOnL2ToAnotherAddressWithNotEnoughValue() public mockGod {
        l1Bridge.setBridgingFee(3);
        l1Bridge.setFlatFee(0.001 ether);
        vm.deal(god, 0.01 ether);

        vm.expectRevert("AviBridge: insufficient ETH value");

        l1Bridge.bridgeETHTo{ value: 0.0001 ether }(l2Receiver, 0, "");
    }

    function test_BridgeDepositsETHOnL2ToAnotherAddress() public mockGod {
        l1Bridge.setBridgingFee(3);
        l1Bridge.setFlatFee(0.001 ether);
        vm.deal(god, 1 ether);

        vm.expectEmit(true, true, false, true);
        emit ETHDepositInitiated(god, l2Receiver, 0.996003 ether, "");
        vm.expectEmit(true, true, false, true);
        emit ETHBridgeInitiated(god, l2Receiver, 0.996003 ether, "");

        l1Bridge.bridgeETHTo{ value: 1 ether }(l2Receiver, 0, "");
    }

    function test_RevertWhenTryingToDepositERC20OnL2WithNotEnoughValue() public mockGod {
        l1Bridge.setBridgingFee(25);
        l1Bridge.setFlatFee(0.001 ether);
        vm.deal(god, 0.01 ether);

        vm.expectRevert("AviBridge: bridging ERC20 must include sufficient ETH value");

        l1Bridge.bridgeERC20{ value: 0.0001 ether }(testTokenAddrL1, testTokenAddrL2, 1 * 10 ** 18, 0, "");
    }

    function test_BridgeDepositsERC20OnL2() public mockGod {
        l1Bridge.setBridgingFee(25);
        l1Bridge.setFlatFee(0.001 ether);
        vm.deal(god, 1 ether);

        testTokenL1.approve(address(l1Bridge), type(uint256).max);

        vm.expectEmit(true, true, false, true);
        emit ERC20BridgeInitiated(testTokenAddrL1, testTokenAddrL2, god, god, 1_000, "");

        l1Bridge.bridgeERC20{ value: 0.001 ether }(testTokenAddrL1, testTokenAddrL2, 1_000, 0, "");
    }

    function test_BridgeDepositsERC20OnL2WithFeeTaken() public mockGod {
        l1Bridge.setBridgingFee(30);
        l1Bridge.setFlatFee(0.001 ether);
        vm.deal(god, 1 ether);

        testTokenL2.approve(address(l1Bridge), type(uint256).max);

        vm.expectEmit(true, true, false, true);
        emit ERC20BridgeInitiated(testTokenAddrL2, testTokenAddrL1, god, god, 970, "");

        l1Bridge.bridgeERC20{ value: 0.001 ether }(testTokenAddrL2, testTokenAddrL1, 1_000, 0, "");
    }

    function test_RevertWhenTryingToBridgeERC20OnL2ToAnotherAddressWithNotEnoughValue() public mockGod {
        l1Bridge.setBridgingFee(25);
        l1Bridge.setFlatFee(0.001 ether);
        vm.deal(god, 0.01 ether);

        vm.expectRevert("AviBridge: bridging ERC20 must include sufficient ETH value");

        l1Bridge.bridgeERC20To{ value: 0.01 ether }(testTokenAddrL1, testTokenAddrL2, l2Receiver, 1 * 10 ** 18, 0, "");
    }

    event ERC20BridgeInitiated(
        address indexed localToken,
        address indexed remoteToken,
        address indexed from,
        address to,
        uint256 amount,
        bytes extraData
    );

    function test_BridgeERC20OnL2ToAnotherAddress() public mockGod {
        l1Bridge.setBridgingFee(25);
        l1Bridge.setFlatFee(0.001 ether);
        vm.deal(god, 1 ether);

        testTokenL1.approve(address(l1Bridge), type(uint256).max);

        vm.expectEmit(true, true, false, true);
        emit ERC20BridgeInitiated(testTokenAddrL1, testTokenAddrL2, god, l2Receiver, 1_000, "");

        l1Bridge.bridgeERC20To{ value: 0.001 ether }(testTokenAddrL1, testTokenAddrL2, l2Receiver, 1_000, 0, "");
    }

    function test_RevertWhenTryingToFinalizeETHWithdrawalAsNonBridge() public {
        vm.prank(bob);

        vm.expectRevert("AviBridge: function can only be called from the other bridge");

        l1Bridge.finalizeETHWithdrawal(bob, alice, 1000 ether, "");
    }

    function test_RevertWhenTryingToFinalizeETHWithdrawalButBridgeIsPaused() public {
        vm.prank(god);
        l1Bridge.setPaused(true);

        test_RevertWhenTryingToFinalizeETHWithdrawalButBridgeIsPaused_INTERNAL();
    }

    function test_RevertWhenTryingToFinalizeETHWithdrawalButBridgeIsPaused_INTERNAL() internal mockL1Messenger {
        vm.expectRevert("AviBridge: paused");

        l1Bridge.finalizeETHWithdrawal(otherBridgeTest, alice, 1000 ether, "");
    }

    function test_RevertWhenTryingToFinalizeETHWithdrawalButETHValueDoesNotMatch() public mockL1Messenger {
        vm.deal(address(l1Messenger), 1 ether);
        vm.expectRevert("AviBridge: amount sent does not match amount required");

        l1Bridge.finalizeETHWithdrawal{ value: 1 ether }(otherBridgeTest, alice, 2 ether, "");
    }

    function test_RevertWhenTryingToFinalizeETHWithdrawalToSelf() public mockL1Messenger {
        vm.deal(address(l1Messenger), 1 ether);
        vm.expectRevert("AviBridge: cannot send to self");

        l1Bridge.finalizeETHWithdrawal{ value: 1 ether }(otherBridgeTest, address(l1Bridge), 1 ether, "");
    }

    function test_RevertWhenTryingToFinalizeETHWithdrawalToMessenger() public mockL1Messenger {
        vm.deal(address(l1Messenger), 1 ether);
        vm.expectRevert("AviBridge: cannot send to messenger");

        l1Bridge.finalizeETHWithdrawal{ value: 1 ether }(otherBridgeTest, payable(AviPredeploys.L1_CROSS_DOMAIN_MESSENGER), 1 ether, "");
    }

    event ETHBridgeFinalized(address indexed from, address indexed to, uint256 amount, bytes extraData);

    function test_FinalizeETHWithdrawal() public mockL1Messenger {
        vm.deal(address(l1Messenger), 1 ether);
        vm.expectEmit(true, true, false, true);
        emit ETHWithdrawalFinalized(otherBridgeTest, alice, 1 ether, "");
        vm.expectEmit(true, true, false, true);
        emit ETHBridgeFinalized(otherBridgeTest, alice, 1 ether, "");

        l1Bridge.finalizeETHWithdrawal{ value: 1 ether }(otherBridgeTest, alice, 1 ether, "");
    }

    function test_RevertWhenTryingToFinalizeERC20WithdrawalAsNonBridge() public {
        vm.prank(bob);

        vm.expectRevert("AviBridge: function can only be called from the other bridge");

        l1Bridge.finalizeERC20Withdrawal(bob, alice, testTokenAddrL1, testTokenAddrL2, 1000, "");
    }

    function test_RevertWhenTryingToFinalizeERC20WithdrawalButBridgeIsPaused() public {
        vm.prank(god);
        l1Bridge.setPaused(true);

        test_RevertWhenTryingToFinalizeERC20WithdrawalButBridgeIsPaused_INTERNAL();
    }

    function test_RevertWhenTryingToFinalizeERC20WithdrawalButBridgeIsPaused_INTERNAL() internal mockL1Messenger {
        vm.expectRevert("AviBridge: paused");

        l1Bridge.finalizeERC20Withdrawal(otherBridgeTest, alice, testTokenAddrL1, testTokenAddrL2, 1000, "");
    }

    function test_RevertWhenTryingToSendETHToNonPayableLiquidityPool() public mockGod {
        L1AviBridge noPayableLiquidityPool = new L1AviBridge(true);
        noPayableLiquidityPool.initialize(payable(address(l1Messenger)), payable(mockOptimismPortalAddr), payable(address(noMoneyAllowed)), testTokenAddrL1);
        vm.deal(god, 1 ether);

        vm.expectRevert("Address: call to non-payable");
        (bool success, ) = payable(noPayableLiquidityPool).call{ value: 1 ether }("");
        assertEq(success, false);
    }

    function test_RevertWhenTryingToSendERC20ToNonPayableLiquidityPool() public mockGod {
        L1AviBridge noPayableLiquidityPool = new L1AviBridge(true);
        noPayableLiquidityPool.initialize(payable(address(l1Messenger)), payable(mockOptimismPortalAddr), payable(address(noMoneyAllowed)), testTokenAddrL2);
        noPayableLiquidityPool.setPaused(false);
        vm.deal(god, 1 ether);
        noPayableLiquidityPool.setFlatFee(0.001 ether);

        testTokenL1.approve(address(noPayableLiquidityPool), type(uint256).max);

        vm.expectRevert("AviBridge: transfer of flat fee to flat fee pool failed");
        noPayableLiquidityPool.bridgeERC20{ value: 0.001 ether }(testTokenAddrL1, testTokenAddrL2, 1_000, 0, "");
    }

    function test_RevertWhenTryingToSetOtherBridgeToAddressZero() public mockGod {
        vm.expectRevert("AviBridge: _otherBridge address cannot be zero");

        l1Bridge.setOtherBridge(address(0));
    }

    function test_RevertWhenTryingToSetL1AviTokenAddressToAddressZero() public mockGod {
        vm.expectRevert("AviBridge: _token address cannot be zero");

        l1Bridge.setAviTokenAddress(address(0));
    }

    function test_SetAviTokenAddressWorks() public mockGod {
        l1Bridge.setAviTokenAddress(testTokenAddrL1);

        assertEq(l1Bridge.L1AviToken(), testTokenAddrL1);
    }

    function test_AvailableETHWorks() public mockGod {
        // TODO: Fix this test
        vm.skip(true);
        // l1Bridge.finalizeFastBridgeETH(bob, god, 10 ether, "");

        // assertEq(l1Bridge.availableETH(), 10 ether);
    }

    function test_AvailableERC20Works() public mockGod {
        // TODO: Fix this test
        vm.skip(true);

        l1Bridge.setBridgingFee(25);
        l1Bridge.setFlatFee(0.001 ether);
        vm.deal(god, 1 ether);

        testTokenL1.approve(address(l1Bridge), type(uint256).max);
        testTokenL1.approve(address(liquidityPool), type(uint256).max);
        liquidityPool.receiveERC20(testTokenAddrL1, 1_000);

        // l1Bridge.bridgeERC20{ value: 0.001 ether }(testTokenAddrL1, testTokenAddrL2, 5_000, 0, "");
        // l1Bridge.finalizeFastBridgeERC20(testTokenAddrL1, testTokenAddrL2, bob, god, 2_000, "");

        // assertEq(l1Bridge.availableERC20(testTokenAddrL1), 2_000);
    }

    function test_RevertWhenFailingToSendBridgingFeeToLiquidityPool() public mockGod {
        L1AviBridge testBridge = new L1AviBridge(true);
        testBridge.initialize(payable(address(l1Messenger)), payable(mockOptimismPortalAddr), payable(address(noMoneyAllowed)), testTokenAddrL1);
        testBridge.setBridgingFee(25);
        testBridge.setFlatFee(0.001 ether);
        testBridge.setFlatFeeRecipient(god);
        testBridge.setPaused(false);
        vm.deal(god, 1 ether);

        vm.expectRevert("AviBridge: transfer of bridging fee to liquidity pool failed");
        testBridge.bridgeETH{ value: 1 ether }(0, "");
    }
}
