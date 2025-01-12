// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { Predeploys } from "@eth-optimism/contracts-bedrock/src/libraries/Predeploys.sol";

import { CommonTest } from 'test/__setup__/CommonTest.sol';
import { MessengerHolder } from 'test/__setup__/MessengerHolder.sol';

import { L2AviBridge } from "src/L2/L2AviBridge.sol";
import { AviPredeploys } from "src/libraries/AviPredeploys.sol";

contract L2Bridge is CommonTest, MessengerHolder {
    L2AviBridge l2Bridge;

    constructor() mockGod {
        l2Bridge = new L2AviBridge(true);
        l2Bridge.initialize(payable(address(l2Messenger)), payable(AviPredeploys.L1_STANDARD_BRIDGE), payable(liquidityPool), payable(liquidityPool));
        l2Bridge.setPaused(false);

        // Make the bridge an admin of the liquidity pool
        liquidityPool.addAdmin(address(l2Bridge));
    }

    function test() public override(CommonTest, MessengerHolder) {}

    function test_RevertWhenBridgeReceivesETHFromContract() public {
        vm.prank(address(liquidityPool));
        vm.expectRevert("AviBridge: function can only be called from an EOA");

        payable(address(l2Bridge)).transfer(69 ether);
    }

    function test_RevertWhenNonAdminTriesToAllowToken() public {
        vm.prank(bob);
        vm.expectRevert("AccessControl: account 0x1d96f2f6bef1202e4ce1ff6dad0c2cb002861d3e is missing role 0x0000000000000000000000000000000000000000000000000000000000000000");

        l2Bridge.addAllowedToken(testTokenAddrL2);
    }

    function test_AllowTokenAsAdmin() public mockGod {
        l2Bridge.addAllowedToken(testTokenAddrL2);

        assertEq(l2Bridge.allowedTokens(testTokenAddrL2), true);
    }

    function test_RevertWhenNonAdminTriesToDisallowToken() public {
        vm.prank(bob);
        vm.expectRevert("AccessControl: account 0x1d96f2f6bef1202e4ce1ff6dad0c2cb002861d3e is missing role 0x0000000000000000000000000000000000000000000000000000000000000000");

        l2Bridge.removeAllowedToken(testTokenAddrL2);
    }

    function test_DisallowTokenAsAdmin() public mockGod {
        l2Bridge.addAllowedToken(testTokenAddrL2);
        l2Bridge.removeAllowedToken(testTokenAddrL2);

        assertEq(l2Bridge.allowedTokens(testTokenAddrL2), false);
    }

    function test_L2BridgeIsNeverPaused() public view {
        assertEq(l2Bridge.paused(), false);
    }

    event WithdrawalInitiated(
        address indexed l1Token,
        address indexed l2Token,
        address indexed from,
        address to,
        uint256 amount,
        bytes extraData
    );

    function test_WithdrawalWorks() public mockGod {
        vm.deal(god, 1 ether);
        l2Bridge.setFlatFee(0);

        vm.expectEmit(true, true, false, true);
        emit WithdrawalInitiated(
            address(0),
            Predeploys.LEGACY_ERC20_ETH,
            god,
            god,
            1 ether,
            ""
        );

        (bool success, ) = payable(address(l2Bridge)).call{ value: 1 ether }("");
        assertTrue(success);
    }

    function test_WithdrawalWorksWithFlatFee() public mockGod {
        vm.deal(god, 1 ether);
        l2Bridge.setFlatFee(0.001 ether);

        vm.expectEmit(true, true, false, true);
        emit WithdrawalInitiated(
            address(0),
            Predeploys.LEGACY_ERC20_ETH,
            god,
            god,
            0.999 ether,
            ""
        );

        (bool success, ) = payable(address(l2Bridge)).call{ value: 1 ether }("");
        assertTrue(success);
    }

    function test_WithdrawalWithTokenCannotBeCalledByContract() public {
        vm.prank(address(liquidityPool));
        vm.deal(address(liquidityPool), 0.001 ether);
        vm.expectRevert("AviBridge: function can only be called from an EOA");

        l2Bridge.withdraw{ value: 0.001 ether }(testTokenAddrL2, 1 ether, 0, "");
    }

    function test_WithdrawalOfETHWorks() public mockGod {
        vm.deal(god, 1 ether);
        l2Bridge.setFlatFee(0);

        vm.expectEmit(true, true, false, true);
        emit WithdrawalInitiated(
            address(0),
            Predeploys.LEGACY_ERC20_ETH,
            god,
            god,
            1 ether,
            ""
        );

        l2Bridge.withdraw{ value: 1 ether }(Predeploys.LEGACY_ERC20_ETH, 1 ether, 0, "");
    }

    function test_WithdrawToOfETHWorks() public mockGod {
        vm.deal(god, 1 ether);
        l2Bridge.setFlatFee(0);

        vm.expectEmit(true, true, false, true);
        emit WithdrawalInitiated(
            address(0),
            Predeploys.LEGACY_ERC20_ETH,
            god,
            bob,
            1 ether,
            ""
        );

        l2Bridge.withdrawTo{ value: 1 ether }(Predeploys.LEGACY_ERC20_ETH, bob, 1 ether, 0, "");
    }

    function test_CannotFastWithdrawETHWithoutItBeingAllowed() public mockGod {
        vm.deal(god, 1 ether);
        l2Bridge.setFlatFee(0);

        vm.expectRevert("L2AviBridge: token not allowed to be fast bridged");

        l2Bridge.fastWithdrawTo{ value: 1 ether }(Predeploys.LEGACY_ERC20_ETH, god, 1 ether, 0, "");
    }

    event FastWithdrawalInitiated(
        address indexed l1Token,
        address indexed l2Token,
        address indexed from,
        address to,
        uint256 amount,
        bytes extraData
    );

    function test_CanFastWithdrawETHWhenAllowed() public mockGod {
        vm.deal(god, 1.001 ether);
        l2Bridge.addAllowedToken(Predeploys.LEGACY_ERC20_ETH);

        vm.expectEmit(true, true, false, true);
        emit FastWithdrawalInitiated(
            address(0),
            Predeploys.LEGACY_ERC20_ETH,
            god,
            god,
            1 ether,
            ""
        );

        l2Bridge.fastWithdrawTo{ value: 1 ether }(Predeploys.LEGACY_ERC20_ETH, god, 1 ether, 0, "");
    }

    function test_WithdrawalOfMintableTokenWorks() public mockGod {
        newL2Contract.mint(god, 1);
        l2Bridge.setFlatFee(0);

        vm.expectEmit(true, true, false, true);
        emit WithdrawalInitiated(
            newL1,
            newL2,
            god,
            god,
            1,
            ""
        );

        l2Bridge.withdraw(newL2, 1, 0, "");
    }

    function test_l1TokenBridgeGetter() public view {
        assertEq(l2Bridge.l1TokenBridge(), AviPredeploys.L1_STANDARD_BRIDGE);
    }

    function test_FinalizeDepositOfETHWorks() public mockL2Messenger {
        vm.deal(AviPredeploys.L2_CROSS_DOMAIN_MESSENGER, 1 ether);

        l2Bridge.finalizeDeposit{ value: 1 ether }(address(0), Predeploys.LEGACY_ERC20_ETH, god, god, 1 ether, "");
    }

    function test_FinalizeDepositOfERC20Works() public mockL2Messenger {
        l2Bridge.finalizeDeposit(newL1, newL2, god, god, 1, "");
    }

    function test_RevertsWhenTryingToFinalizeDepositAsNonMessenger() public {
        vm.prank(bob);
        vm.deal(bob, 1 ether);
        vm.expectRevert("AviBridge: function can only be called from the other bridge");

        l2Bridge.finalizeDeposit{ value: 1 ether }(newL1, newL2, god, god, 1, "");
        assertEq(address(l2Bridge).balance, 0);
        assertEq(address(bob).balance, 1 ether);
    }
}
