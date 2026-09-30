// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {PoolTestBase} from "../unit/PoolTestBase.sol";
import {DataTypes} from "../../src/libraries/DataTypes.sol";

contract IndexPhaseTest is PoolTestBase {
    // Catches user-favouring round-to-nearest at a non-unit index, and
    // aggregate principal updates that strand another user's accrued claim.
    function testFuzz_IdleAccrualNeverCreatesValueAcrossPartialAndFullExits(
        uint32 firstIdle,
        uint32 secondIdle,
        uint128 rawCredit,
        uint16 rawFraction
    ) public {
        _deposit(alice, USDT_ID, address(usdt), 100_000e18);
        _deposit(bob, USDT_ID, address(usdt), 20_000e18);
        _deposit(alice, WETH_ID, address(weth), 20e18);
        _deposit(bob, WETH_ID, address(weth), 20e18);
        _borrow(alice, WETH_ID, USDT_ID, 20_000e18, 0.05e18);
        _borrow(bob, WETH_ID, USDT_ID, 15_000e18, 0.05e18);
        vm.warp(block.timestamp + bound(uint256(firstIdle), 1, 365 days));
        uint256 credit = bound(uint256(rawCredit), 1e6, 100e18);
        uint256 claimBefore = pool.getUserDepositBalance(USDT_ID, bob);
        uint256 walletBefore = usdt.balanceOf(bob);
        _deposit(bob, USDT_ID, address(usdt), credit);
        assertEq(walletBefore - usdt.balanceOf(bob), credit);
        uint256 claimAfter = pool.getUserDepositBalance(USDT_ID, bob);
        assertLe(claimAfter - claimBefore, credit);
        uint256 supplyIndex = pool.getReserve(USDT_ID).supplyLiquidityIndex;
        assertLe(credit - (claimAfter - claimBefore), supplyIndex / RAY + 1);

        uint256 requested = claimAfter * bound(uint256(rawFraction), 1, 9_999) / 10_000;
        walletBefore = usdt.balanceOf(bob);
        vm.prank(bob);
        pool.withdraw(USDT_ID, requested);
        uint256 burnt = claimAfter - pool.getUserDepositBalance(USDT_ID, bob);
        assertEq(usdt.balanceOf(bob) - walletBefore, requested);
        assertGe(burnt, requested);
        assertLe(burnt - requested, supplyIndex / RAY + 1);

        uint256 debtBefore = pool.getUserBorrowBalance(USDT_ID, alice);
        uint256 repayAmount = debtBefore * bound(uint256(rawFraction), 1, 9_999) / 10_000;
        walletBefore = usdt.balanceOf(alice);
        vm.startPrank(alice);
        usdt.approve(address(pool), type(uint256).max);
        pool.repay(WETH_ID, USDT_ID, 0, repayAmount);
        vm.stopPrank();
        uint256 cancelled = debtBefore - pool.getUserBorrowBalance(USDT_ID, alice);
        assertEq(walletBefore - usdt.balanceOf(alice), repayAmount);
        assertLe(cancelled, repayAmount);
        assertLe(repayAmount - cancelled, pool.getReserve(USDT_ID).borrowLiquidityIndex / RAY + 1);

        vm.warp(pool.getReserve(USDT_ID).lastUpdateTimestamp + bound(uint256(secondIdle), 1, 365 days));
        _close(alice);
        _close(bob);
        assertEq(pool.getReserve(USDT_ID).totalBorrows, 0);
        assertEq(pool.getUserBorrowBalance(USDT_ID, alice), 0);
        assertEq(pool.getUserBorrowBalance(USDT_ID, bob), 0);
        uint256 aliceClaim = pool.getUserDepositBalance(USDT_ID, alice);
        uint256 bobClaim = pool.getUserDepositBalance(USDT_ID, bob);
        assertGe(usdt.balanceOf(address(pool)), aliceClaim + bobClaim);
        vm.prank(alice);
        pool.withdraw(USDT_ID, aliceClaim);
        vm.prank(bob);
        pool.withdraw(USDT_ID, bobClaim);
        assertEq(pool.getReserve(USDT_ID).totalDeposits, 0);
        assertEq(pool.getUserDepositBalance(USDT_ID, alice), 0);
        assertEq(pool.getUserDepositBalance(USDT_ID, bob), 0);
        // Closing a loan restores the entire fixed collateral claim at a unit index.
        assertEq(pool.getUserDepositBalance(WETH_ID, alice), 20e18);
        assertEq(pool.getUserDepositBalance(WETH_ID, bob), 20e18);
    }

    function _close(address user) internal {
        uint256 debt = pool.getUserBorrowBalance(USDT_ID, user);
        uint256 wallet = usdt.balanceOf(user);
        vm.startPrank(user);
        usdt.approve(address(pool), type(uint256).max);
        pool.repay(WETH_ID, USDT_ID, 0, type(uint256).max);
        vm.stopPrank();
        assertEq(wallet - usdt.balanceOf(user), debt);
    }
}
