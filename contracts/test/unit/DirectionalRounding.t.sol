// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {DataTypes} from "../../src/libraries/DataTypes.sol";
import {PoolTestBase} from "./PoolTestBase.sol";

contract DirectionalRoundingTest is PoolTestBase {
    function setUp() public override {
        super.setUp();
        _deposit(alice, USDT_ID, address(usdt), 22_000e18);
        _deposit(bob, WETH_ID, address(weth), 10e18);
        _borrow(bob, WETH_ID, USDT_ID, 20_000e18, 0.05e18);
        vm.warp(block.timestamp + 10 * 365 days);
        _deposit(alice, USDT_ID, address(usdt), 1e18);
        assertGt(pool.getReserve(USDT_ID).supplyLiquidityIndex, 3e18);
        assertGt(pool.getReserve(USDT_ID).borrowLiquidityIndex, 3e18);
    }

    function _repayFully() internal {
        vm.startPrank(bob);
        usdt.approve(address(pool), type(uint256).max);
        pool.repay(WETH_ID, USDT_ID, 0, type(uint256).max);
        vm.stopPrank();
    }

    function test_TinyWithdrawalsCannotLeaveClaimUnchanged() public {
        _repayFully();
        for (uint256 i; i < 10; ++i) {
            uint256 beforeClaim = pool.getUserDepositBalance(USDT_ID, alice);
            vm.prank(alice);
            pool.withdraw(USDT_ID, 1);
            assertLt(pool.getUserDepositBalance(USDT_ID, alice), beforeClaim);
        }
    }

    function testFuzz_WithdrawalBurnCoversTransferredAmount(uint16 rawAmount) public {
        _repayFully();
        uint256 amount = bound(uint256(rawAmount), 1, 1_000);
        uint256 beforeClaim = pool.getUserDepositBalance(USDT_ID, alice);
        uint256 beforeTokens = usdt.balanceOf(alice);
        vm.prank(alice);
        pool.withdraw(USDT_ID, amount);
        assertGe(beforeClaim - pool.getUserDepositBalance(USDT_ID, alice), amount);
        assertEq(usdt.balanceOf(alice) - beforeTokens, amount);
    }

    function test_DepositBelowOneScaledUnitRevertsWithoutTakingTokens() public {
        uint256 beforeTokens = usdt.balanceOf(bob);
        vm.startPrank(bob);
        usdt.approve(address(pool), 3);
        vm.expectRevert("SupplyModule: amount below index precision");
        pool.deposit(USDT_ID, 3);
        vm.stopPrank();
        assertEq(usdt.balanceOf(bob), beforeTokens);
        assertEq(pool.getUserDepositBalance(USDT_ID, bob), 0);
    }

    function testFuzz_DepositCreditDoesNotExceedPayment(uint16 rawAmount) public {
        uint256 amount = bound(uint256(rawAmount), 5, 1_000);
        uint256 beforeClaim = pool.getUserDepositBalance(USDT_ID, alice);
        _deposit(alice, USDT_ID, address(usdt), amount);
        assertLe(pool.getUserDepositBalance(USDT_ID, alice) - beforeClaim, amount);
    }

    function test_TinyPartialRepaymentRevertsWithoutTakingTokens() public {
        uint256 beforeTokens = usdt.balanceOf(bob);
        uint256 beforeDebt = pool.getUserBorrowBalance(USDT_ID, bob);
        vm.startPrank(bob);
        usdt.approve(address(pool), 1);
        vm.expectRevert("BorrowModule: amount below index precision");
        pool.repay(WETH_ID, USDT_ID, 0, 1);
        vm.stopPrank();
        assertEq(usdt.balanceOf(bob), beforeTokens);
        assertEq(pool.getUserBorrowBalance(USDT_ID, bob), beforeDebt);
    }

    function test_PartialRepaymentCannotForgiveMoreThanPaid() public {
        uint256 beforeDebt = pool.getUserBorrowBalance(USDT_ID, bob);
        vm.startPrank(bob);
        usdt.approve(address(pool), 8);
        pool.repay(WETH_ID, USDT_ID, 0, 8);
        vm.stopPrank();
        assertLe(beforeDebt - pool.getUserBorrowBalance(USDT_ID, bob), 8);
    }

    function testFuzz_BorrowedTokensHaveMatchingOrGreaterDebt(uint16 rawAmount) public {
        _repayFully();
        oracle.setPrice(wethFeed, 1e18);
        uint256 amount = bound(uint256(rawAmount), 1, 1_000);
        uint256 beforeTokens = usdt.balanceOf(bob);
        _borrow(bob, WETH_ID, USDT_ID, amount, 0.05e18);
        assertGe(pool.getUserBorrowBalance(USDT_ID, bob), amount);
        assertGt(pool.getPosition(bob, 1).scaledDebt, 0);
        assertTrue(pool.checkPositionHealth(bob, 1));
        assertEq(usdt.balanceOf(bob) - beforeTokens, amount);
    }

    function test_FullWithdrawalConsumesAllRemainingClaim() public {
        _repayFully();
        uint256 claim = pool.getUserDepositBalance(USDT_ID, alice);
        vm.prank(alice);
        pool.withdraw(USDT_ID, claim);
        assertEq(pool.getUserDepositBalance(USDT_ID, alice), 0);
        assertEq(pool.getReserve(USDT_ID).totalDeposits, 0);
    }

    function test_PartialCollateralReleaseFollowsScaledDebtRemoved() public {
        _repayFully();
        oracle.setPrice(wethFeed, 1e18);
        _borrow(bob, WETH_ID, USDT_ID, 20, 0.05e18);
        DataTypes.Position memory beforePosition = pool.getPosition(bob, 1);
        vm.startPrank(bob);
        usdt.approve(address(pool), 8);
        pool.repay(WETH_ID, USDT_ID, 1, 8);
        vm.stopPrank();
        DataTypes.Position memory afterPosition = pool.getPosition(bob, 1);
        uint256 removed = beforePosition.scaledDebt - afterPosition.scaledDebt;
        assertEq(
            beforePosition.collateralLocked - afterPosition.collateralLocked,
            beforePosition.collateralLocked * removed / beforePosition.scaledDebt
        );
    }

    function test_FullDisplayedCollateralCanBeLockedAndReturned() public {
        _repayFully();
        _deposit(bob, USDT_ID, address(usdt), 21);
        assertEq(pool.getUserDepositBalance(USDT_ID, bob), 21);
        oracle.setPrice(wethFeed, 1.3e18);
        _borrow(bob, USDT_ID, WETH_ID, 12, 0.05e18);
        assertEq(pool.getUserDepositBalance(USDT_ID, bob), 0);
        assertEq(pool.getPosition(bob, 1).collateralLocked, 21);
        vm.startPrank(bob);
        weth.approve(address(pool), type(uint256).max);
        pool.repay(USDT_ID, WETH_ID, 1, type(uint256).max);
        vm.stopPrank();
        assertEq(pool.getUserBorrowBalance(WETH_ID, bob), 0);
        assertEq(pool.getUserDepositBalance(USDT_ID, bob), 21);
    }

    function test_ZeroRoundedCollateralRejected() public {
        _repayFully();
        uint256 beforeTokens = usdt.balanceOf(bob);
        vm.prank(bob);
        vm.expectRevert("BorrowModule: zero collateral");
        pool.borrow(WETH_ID, USDT_ID, 1, 0.05e18);
        assertEq(usdt.balanceOf(bob), beforeTokens);
    }
}
