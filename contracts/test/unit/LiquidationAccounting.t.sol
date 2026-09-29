// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {PoolTestBase} from "./PoolTestBase.sol";
import {DataTypes} from "../../src/libraries/DataTypes.sol";

contract LiquidationAccountingTest is PoolTestBase {
    function setUp() public override {
        super.setUp();
        _deposit(alice, USDT_ID, address(usdt), 22_000e18);
        _deposit(alice, WETH_ID, address(weth), 10e18);
        _deposit(bob, WETH_ID, address(weth), 10e18);
        _borrow(bob, WETH_ID, USDT_ID, 10_000e18, 0.05e18);
    }

    function _liquidateBob() internal {
        vm.startPrank(alice);
        usdt.approve(address(pool), type(uint256).max);
        pool.liquidatePosition(bob, 0);
        vm.stopPrank();
    }

    function test_LiquidationRemovesAllPaidCollateralFromReserve() public {
        DataTypes.ReserveData memory beforeReserve = pool.getReserve(WETH_ID);
        DataTypes.Position[] memory positions = pool.getUserPositions(bob);
        uint256 locked = positions[0].collateralLocked;
        uint256 aliceBefore = weth.balanceOf(alice);
        uint256 bobBefore = weth.balanceOf(bob);
        oracle.setPrice(wethFeed, 2_000e18);
        _liquidateBob();
        assertEq(pool.getReserve(WETH_ID).totalDeposits, beforeReserve.totalDeposits - locked);
        assertEq(weth.balanceOf(alice) - aliceBefore + weth.balanceOf(bob) - bobBefore, locked);
        assertEq(pool.getReserve(WETH_ID).totalDeposits, weth.balanceOf(address(pool)));
        assertEq(pool.getUserDepositBalance(WETH_ID, alice), 10e18);
    }

    function testFuzz_LiquidationConservesRemainingDeposits(uint256 price) public {
        price = bound(price, 1_000e18, 2_680e18);
        oracle.setPrice(wethFeed, price);
        _liquidateBob();
        uint256 claims = pool.getUserDepositBalance(WETH_ID, alice) + pool.getUserDepositBalance(WETH_ID, bob);
        assertEq(pool.getReserve(WETH_ID).totalDeposits, claims);
        assertEq(weth.balanceOf(address(pool)), claims);
        vm.prank(alice);
        pool.withdraw(WETH_ID, 10e18);
        uint256 remaining = pool.getUserDepositBalance(WETH_ID, bob);
        vm.prank(bob);
        pool.withdraw(WETH_ID, remaining);
        assertEq(pool.getReserve(WETH_ID).totalDeposits, 0);
        assertEq(weth.balanceOf(address(pool)), 0);
    }

    function test_FailedLiquidationLeavesReserveAndClaimsUnchanged() public {
        bytes32 beforeReserve = keccak256(abi.encode(pool.getReserve(WETH_ID)));
        uint256 balance = weth.balanceOf(address(pool));
        vm.prank(alice);
        vm.expectRevert("LiquidationModule: position healthy");
        pool.liquidatePosition(bob, 0);
        assertEq(keccak256(abi.encode(pool.getReserve(WETH_ID))), beforeReserve);
        assertEq(weth.balanceOf(address(pool)), balance);
        assertEq(pool.getUserPositions(bob).length, 1);
    }
}
