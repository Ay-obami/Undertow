// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {PoolTestBase} from "./PoolTestBase.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {DataTypes} from "../../src/libraries/DataTypes.sol";

contract AggregateAccountingTest is PoolTestBase {
    function _openTwoBorrowers() internal {
        _deposit(alice, USDT_ID, address(usdt), 22_000e18);
        _deposit(alice, WETH_ID, address(weth), 10e18);
        _deposit(bob, WETH_ID, address(weth), 10e18);
        _borrow(alice, WETH_ID, USDT_ID, 10_000e18, 0.05e18);
        _borrow(bob, WETH_ID, USDT_ID, 10_000e18, 0.05e18);
    }

    function _repayUsdt(address user, uint256 amount) internal {
        vm.startPrank(user);
        usdt.approve(address(pool), type(uint256).max);
        pool.repay(WETH_ID, USDT_ID, 0, amount);
        vm.stopPrank();
    }

    function _assertUsdtClaims() internal view {
        uint256 debt = pool.getUserBorrowBalance(USDT_ID, alice) + pool.getUserBorrowBalance(USDT_ID, bob);
        DataTypes.ReserveData memory reserve = pool.getReserve(USDT_ID);
        assertApproxEqAbs(reserve.totalBorrows, debt, 2);
        assertApproxEqAbs(reserve.totalDeposits, pool.getUserDepositBalance(USDT_ID, alice), 1);
        assertGe(usdt.balanceOf(address(pool)) + debt + 2, reserve.totalDeposits);
    }

    function test_FullRepaymentPreservesOtherBorrowersAccruedDebt() public {
        _openTwoBorrowers();
        vm.warp(block.timestamp + 365 days);
        _repayUsdt(alice, type(uint256).max);
        assertGt(pool.getUserBorrowBalance(USDT_ID, bob), 10_000e18);
        _assertUsdtClaims();
    }

    function test_SupplierCanWithdrawAccruedClaimAfterAllDebtIsRepaid() public {
        _openTwoBorrowers();
        vm.warp(block.timestamp + 365 days);
        _repayUsdt(alice, type(uint256).max);
        _repayUsdt(bob, type(uint256).max);
        uint256 claim = pool.getUserDepositBalance(USDT_ID, alice);
        assertGt(claim, 22_000e18);
        vm.prank(alice);
        pool.withdraw(USDT_ID, claim);
        assertEq(pool.getReserve(USDT_ID).totalDeposits, 0);
        assertEq(pool.getReserve(USDT_ID).totalBorrows, 0);
        assertEq(pool.getUserDepositBalance(USDT_ID, alice), 0);
    }

    function testFuzz_PartialAndFullRepaymentConserveClaims(uint32 rawElapsed, uint16 rawFraction) public {
        _openTwoBorrowers();
        vm.warp(block.timestamp + bound(uint256(rawElapsed), 1 days, 365 days));
        uint256 fraction = bound(uint256(rawFraction), 1, 9_999);
        uint256 debt = pool.getUserBorrowBalance(USDT_ID, alice);
        _repayUsdt(alice, debt * fraction / 10_000);
        _assertUsdtClaims();
        vm.warp(block.timestamp + 30 days);
        _repayUsdt(alice, type(uint256).max);
        _assertUsdtClaims();
        _repayUsdt(bob, type(uint256).max);
        _assertUsdtClaims();
        assertEq(pool.getReserve(USDT_ID).totalBorrows, 0);
    }

    function test_AccruedCollateralCanBeLiquidatedAboveOriginalDepositTotal() public {
        _deposit(alice, USDT_ID, address(usdt), 100_000e18);
        _deposit(alice, WBTC_ID, address(wbtc), 10e18);
        _deposit(bob, WETH_ID, address(weth), 10e18);
        _borrow(alice, WBTC_ID, WETH_ID, 9e18, 0.05e18);
        vm.warp(block.timestamp + 365 days);
        vm.startPrank(alice);
        weth.approve(address(pool), type(uint256).max);
        pool.repay(WBTC_ID, WETH_ID, 0, type(uint256).max);
        vm.stopPrank();
        assertGt(pool.getUserDepositBalance(WETH_ID, bob), 10e18);
        _borrow(bob, WETH_ID, USDT_ID, 25_000e18, 0.05e18);
        DataTypes.Position memory pos = pool.getPosition(bob, 0);
        assertGt(pos.collateralLocked, 10e18);
        oracle.setPrice(wethFeed, 1_000e18);
        vm.startPrank(alice);
        usdt.approve(address(pool), type(uint256).max);
        pool.liquidate(bob, 0);
        vm.stopPrank();
        assertApproxEqAbs(pool.getReserve(WETH_ID).totalDeposits, pool.getUserDepositBalance(WETH_ID, bob), 1);
        assertEq(pool.getReserve(USDT_ID).totalBorrows, 0);
    }

    function test_LockedCollateralStaysFixedWhileFreeDepositsAccrue() public {
        _openTwoBorrowers();
        _deposit(alice, WBTC_ID, address(wbtc), 10e18);
        _borrow(alice, WBTC_ID, WETH_ID, 15e18, 0.05e18);
        uint256 locked = pool.getPosition(alice, 0).collateralLocked + pool.getPosition(bob, 0).collateralLocked;
        vm.warp(block.timestamp + 180 days);
        // A small deposit persists accrued indexes and totals without changing locks.
        _deposit(alice, WETH_ID, address(weth), 1e18);
        uint256 free = pool.getUserDepositBalance(WETH_ID, alice) + pool.getUserDepositBalance(WETH_ID, bob);
        assertEq(pool.getPosition(alice, 0).collateralLocked + pool.getPosition(bob, 0).collateralLocked, locked);
        assertApproxEqAbs(pool.getReserve(WETH_ID).totalDeposits, free + locked, 2);
    }
    function test_LiquidatingOneBorrowerPreservesOtherAccruedClaims() public {
        _openTwoBorrowers();
        vm.warp(block.timestamp + 365 days);
        uint256 bobDebt = pool.getUserBorrowBalance(USDT_ID, bob);
        oracle.setPrice(wethFeed, 2_000e18);
        vm.startPrank(bob);
        usdt.approve(address(pool), type(uint256).max);
        pool.liquidate(alice, 0);
        vm.stopPrank();
        assertEq(pool.getUserBorrowBalance(USDT_ID, bob), bobDebt);
        _assertUsdtClaims();
        uint256 free = pool.getUserDepositBalance(WETH_ID, alice) + pool.getUserDepositBalance(WETH_ID, bob);
        uint256 locked = pool.getPosition(bob, 0).collateralLocked;
        assertApproxEqAbs(pool.getReserve(WETH_ID).totalDeposits, free + locked, 2);
        _repayUsdt(bob, type(uint256).max);
        assertEq(pool.getReserve(USDT_ID).totalBorrows, 0);
    }

    function test_BorrowCapIncludesAccruedDebtAfterAnotherBorrowerRepays() public {
        MockERC20 token = new MockERC20("Capped", "CAP");
        pool.addReserve(
            DataTypes.ReserveConfig({
                name: "Capped",
                tokenAddress: address(token),
                priceFeed: usdtFeed,
                interestStrategy: address(strategy),
                liquidationThreshold: LIQ_THRESHOLD,
                ltv: LTV,
                slope1: SLOPE1,
                slope2: SLOPE2,
                baseInterestRate: BASE_RATE,
                optimalUtilization: OPT_UTIL,
                liquidationBonus: LIQ_BONUS,
                reserveFactor: RESERVE_FACTOR,
                borrowCap: 20_000e18,
                supplyCap: SUPPLY_CAP,
                isActive: true,
                isBorrowable: true
            })
        );
        bytes32 id = pool.getReserveId("Capped");
        token.mint(alice, 1_000_000e18);
        _deposit(alice, id, address(token), 22_000e18);
        _deposit(alice, WETH_ID, address(weth), 10e18);
        _deposit(bob, WETH_ID, address(weth), 10e18);
        _borrow(alice, WETH_ID, id, 10_000e18, 0.05e18);
        _borrow(bob, WETH_ID, id, 10_000e18, 0.05e18);
        vm.warp(block.timestamp + 365 days);
        vm.startPrank(alice);
        token.approve(address(pool), type(uint256).max);
        pool.repay(WETH_ID, id, 0, type(uint256).max);
        vm.stopPrank();
        vm.prank(bob);
        vm.expectRevert("ReserveLib: borrow cap exceeded");
        pool.borrow(WETH_ID, id, 10_000e18, 0.05e18);
    }

}
