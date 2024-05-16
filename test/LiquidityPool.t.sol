// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { CommonTest, TestableLiquidityPool } from 'test/__setup__/CommonTest.sol';

contract LiquidityPool_Coverage is CommonTest {
    TestableLiquidityPool mockedLiquidityPool;
    event AdminAdded(address adminAddress);
    event AdminRemoved(address adminAddress);

    constructor() mockGod {
        mockedLiquidityPool = new TestableLiquidityPool();
        vm.deal(address(mockedLiquidityPool), 10_000 ether);
    }

    function test_AddAdmin() public mockGod {
        vm.expectEmit(true, true, false, false);

        emit AdminAdded(alice);

        mockedLiquidityPool.addAdmin(alice);

        assertEq(mockedLiquidityPool.getNumAdmins(), 2);
    }

    function test_RevertWhenTryingToAddAdminThatAlreadyExists() public mockGod {
        mockedLiquidityPool.addAdmin(alice);

        vm.expectRevert("Admin already added.");
        mockedLiquidityPool.addAdmin(alice);
    }

    function test_RevertWhenTryingToAddAdminAsNonAdmin() public {
        vm.prank(bob);

        vm.expectRevert("AccessControl: account 0x1d96f2f6bef1202e4ce1ff6dad0c2cb002861d3e is missing role 0x0000000000000000000000000000000000000000000000000000000000000000");
        mockedLiquidityPool.addAdmin(alice);
    }

    function test_RevertWhenTryingToRemoveOnlyAdmin() public mockGod {
        vm.expectRevert("Cannot remove the only admin.");
        mockedLiquidityPool.removeAdmin(god);
    }

    function test_RevertWhenTryingToRemoveAdminThatDoesNotExist() public mockGod {
        vm.expectRevert("Address is not a recognized admin.");
        mockedLiquidityPool.removeAdmin(bob);
    }

    function test_RemovingAnAdminEmitsEvent() public mockGod {
        mockedLiquidityPool.addAdmin(alice);

        vm.expectEmit(true, true, false, false);

        emit AdminRemoved(alice);

        mockedLiquidityPool.removeAdmin(alice);

        assertEq(mockedLiquidityPool.getNumAdmins(), 1);
    }

    function test_SendETH() public mockGod {
        mockedLiquidityPool.sendETH(bob, 1000 ether);
        assertEq(bob.balance, 1000 ether);
        assertEq(mockedLiquidityPool.getBalance(), 9000 ether);
    }

    function test_RevertWhenTryingToSendETHToZeroAddress() public mockGod {
        vm.expectRevert("LiquidityPool: _to address cannot be zero");
        mockedLiquidityPool.sendETH(address(0), 1000 ether);
    }

    function test_RevertWhenTryingToSendMoreETHThanAvailable() public mockGod {
        vm.expectRevert("failed to send ether");
        mockedLiquidityPool.sendETH(bob, 10_001 ether);
    }

    function test_RevertWhenNonAdminTriesToSendETH() public {
        vm.prank(bob);

        vm.expectRevert("AccessControl: account 0x1d96f2f6bef1202e4ce1ff6dad0c2cb002861d3e is missing role 0x0000000000000000000000000000000000000000000000000000000000000000");
        mockedLiquidityPool.sendETH(bob, 1000 ether);
    }

    function test_ShouldReceiveETH() public {
        vm.deal(bob, 1000 ether);
        vm.prank(bob);
        (bool sent, ) = address(mockedLiquidityPool).call{value: 1000 ether}("");
        assertEq(sent, true);
        assertEq(mockedLiquidityPool.getBalance(), 11_000 ether);
    }

    function test_ShouldReceiveERC20() public mockGod {
        testTokenL1.increaseAllowance(address(mockedLiquidityPool), 1_000);

        mockedLiquidityPool.receiveERC20(god, testTokenAddrL1, 1_000);

        assertEq(mockedLiquidityPool.getERC20Balance(testTokenAddrL1), 1_000);
    }

    function test_ShouldBeAbleToSendERC20() public mockGod {
        // Give the liquidity pool some liquidity
        testTokenL1.increaseAllowance(address(mockedLiquidityPool), 1_000);
        mockedLiquidityPool.receiveERC20(god, testTokenAddrL1, 1_000);

        // Send the liquidity to bob
        mockedLiquidityPool.sendERC20(bob, testTokenAddrL1, 1_000);

        assertEq(testTokenL1.balanceOf(bob), 1_000);
        assertEq(mockedLiquidityPool.getERC20Balance(testTokenAddrL1), 0);
    }
}
