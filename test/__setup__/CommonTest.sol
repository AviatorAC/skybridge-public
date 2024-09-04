// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { Test } from 'forge-std/Test.sol';
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

import { TestToken } from 'test/__setup__/TestToken.sol';
import { TestNFT } from 'test/__setup__/TestNFT.sol';
import { OptimismMintables } from 'test/__setup__/OptimismMintables.sol';

import { LiquidityPool } from 'src/L1/LiquidityPool.sol';

contract CommonTest is Test, OptimismMintables {
    address alice;
    address bob;
    address god = address(0x42069);

    address payable flatFeeRecepient = payable(address(0x1337));

    ERC20 testTokenL1;
    address testTokenAddrL1;

    ERC20 testTokenL2;
    address testTokenAddrL2;

    LiquidityPool liquidityPool;

    ERC721 testNFTL1;
    address testNFTAddrL1;

    uint256 public constant NFT_ID = 1;

    ERC721 testNFTL2;
    address testNFTAddrL2;

    constructor() mockGod {
        alice = makeAddr("alice");
        bob = makeAddr("bob");

        testTokenL1 = new TestToken();
        testTokenAddrL1 = address(testTokenL1);

        testTokenL2 = new TestToken();
        testTokenAddrL2 = address(testTokenL2);

        liquidityPool = new LiquidityPool(true);
        liquidityPool.initialize();
        vm.deal(address(liquidityPool), 10_000 ether);

        // No, god isn't technically a bridge. But shh, makes tests easier
        liquidityPool.addBridge(god);

        testNFTL1 = new TestNFT();
        testNFTAddrL1 = address(testNFTL1);

        testNFTL2 = new TestNFT();
        testNFTAddrL2 = address(testNFTL2);
    }

    modifier mockGod() {
        vm.startPrank(god);

        _;

        vm.stopPrank();
    }

    function test() public override virtual {}
}


/// @notice An extension of our liquidity pool contract that exposes internal state for testing.
contract TestableLiquidityPool is LiquidityPool {
    constructor() LiquidityPool(true) {}

    /// @notice Returns the number of admins.
    function getNumAdmins() external view returns (uint) {
        return _numAdmins;
    }
}
