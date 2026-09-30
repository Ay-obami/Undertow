// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {PoolTestBase} from "./PoolTestBase.sol";
import {DataTypes} from "../../src/libraries/DataTypes.sol";

/// @notice Documents full-debt liquidation economics and pause escape behavior.
contract LiquidationPolicyTest is PoolTestBase {
    function _open() internal returns (uint256 locked) {
        _deposit(alice, USDT_ID, address(usdt), 100_000e18);
        _deposit(bob, WETH_ID, address(weth), 10e18);
        _borrow(bob, WETH_ID, USDT_ID, 20_000e18, 0.05e18);
        locked = pool.getPosition(bob, 0).collateralLocked;
    }

    function test_DeepUnderwaterLiquidationRequiresFullPayment() public {
        uint256 locked = _open();
        oracle.setPrice(wethFeed, 1_000e18);
        assertLt(locked * 1_000, 20_000e18);
        assertFalse(pool.checkPositionHealth(bob, 0));
        uint256 cashBefore = usdt.balanceOf(address(pool));
        uint256 buyerBefore = usdt.balanceOf(alice);
        uint256 collateralBefore = weth.balanceOf(alice);
        vm.startPrank(alice);
        usdt.approve(address(pool), type(uint256).max);
        pool.liquidate(bob, 0);
        vm.stopPrank();
        assertEq(buyerBefore - usdt.balanceOf(alice), 20_000e18);
        assertEq(usdt.balanceOf(address(pool)) - cashBefore, 20_000e18);
        assertEq(weth.balanceOf(alice) - collateralBefore, locked);
        assertEq(pool.getUserBorrowBalance(USDT_ID, bob), 0);
        // The liquidator willingly pays more than the collateral's market value.
        assertLt(locked * 1_000, buyerBefore - usdt.balanceOf(alice));
    }

    function test_UnfundedUnderwaterLiquidationKeepsDebtAndCollateral() public {
        uint256 locked = _open();
        oracle.setPrice(wethFeed, 1_000e18);
        uint256 cashBefore = usdt.balanceOf(address(pool));
        address unfunded = makeAddr("unfunded");
        vm.startPrank(unfunded);
        usdt.approve(address(pool), type(uint256).max);
        vm.expectRevert();
        pool.liquidate(bob, 0);
        vm.stopPrank();
        DataTypes.Position memory pos = pool.getPosition(bob, 0);
        assertTrue(pos.isOpen);
        assertEq(pos.collateralLocked, locked);
        assertEq(pool.getUserBorrowBalance(USDT_ID, bob), 20_000e18);
        assertEq(usdt.balanceOf(address(pool)), cashBefore);
    }

    function test_InactiveReservesStillAllowRepaymentAndLiquidation() public {
        _open();
        pool.setReserveActive(WETH_ID, false);
        pool.setReserveActive(USDT_ID, false);
        vm.startPrank(bob);
        usdt.approve(address(pool), type(uint256).max);
        pool.repay(WETH_ID, USDT_ID, 0, type(uint256).max);
        vm.stopPrank();
        assertEq(pool.getUserBorrowBalance(USDT_ID, bob), 0);
        assertEq(pool.getUserDepositBalance(WETH_ID, bob), 10e18);
        vm.prank(bob);
        vm.expectRevert("ReserveLib: reserve inactive");
        pool.withdraw(WETH_ID, 1e18);
        pool.setReserveActive(WETH_ID, true);
        vm.prank(bob);
        pool.withdraw(WETH_ID, 10e18);
        assertEq(pool.getUserDepositBalance(WETH_ID, bob), 0);

        // A separate unhealthy position remains liquidatable while paused.
        pool.setReserveActive(USDT_ID, true);
        _deposit(bob, WETH_ID, address(weth), 10e18);
        _borrow(bob, WETH_ID, USDT_ID, 20_000e18, 0.05e18);
        pool.setReserveActive(WETH_ID, false);
        pool.setReserveActive(USDT_ID, false);
        oracle.setPrice(wethFeed, 2_500e18);
        vm.startPrank(alice);
        usdt.approve(address(pool), type(uint256).max);
        pool.liquidate(bob, 1);
        vm.stopPrank();
        assertEq(pool.getUserBorrowBalance(USDT_ID, bob), 0);
    }
}
