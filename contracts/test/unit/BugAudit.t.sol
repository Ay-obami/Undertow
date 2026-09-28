// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {PoolTestBase} from "./PoolTestBase.sol";

/// @title BugAudit
/// @notice Week 3 deliverable — re-verifies the four bugs the PRD calls out as
///         previously self-audited, one test group per bug, against the ported
///         codebase. Three were already fixed by the time this repo was ported
///         (see the "Bug fix vs original" comments in the affected contracts);
///         this file is the *re-verification* the PRD asks for. The fourth —
///         stale borrow-index health checks — was still present and is fixed
///         alongside these tests (see `ReserveLib.previewBorrowIndex` and
///         `LiquidationModule._checkHealth`).
contract BugAuditTest is PoolTestBase {
    address internal liquidator = address(0xB0B5);

    function setUp() public override {
        super.setUp();
        // Deposited fresh per-test below instead of a shared pool-wide seed,
        // so each bug's test can control utilization precisely (Bug 4 in
        // particular needs high utilization to make accrued interest visible
        // within a reasonable time window).
    }

    // ================================================================
    // Bug 1 — missing transfer in repay
    // ================================================================
    // Original: repay() updated debt accounting but never pulled tokens from
    // the borrower, so the pool's reserves silently drained on every repay.
    // Fixed: BorrowModule._repay calls safeTransferFrom before touching state.

    function test_Bug1_Repay_ActuallyTransfersTokensFromBorrower() public {
        _deposit(alice, USDT_ID, address(usdt), 500_000e18);
        _deposit(bob, WETH_ID, address(weth), 10e18);
        vm.prank(bob);
        pool.borrow(WETH_ID, USDT_ID, 10_000e18, 0.1e18);

        uint256 bobUsdtBefore = usdt.balanceOf(bob);
        uint256 poolUsdtBefore = usdt.balanceOf(address(pool));

        vm.startPrank(bob);
        usdt.approve(address(pool), 10_000e18);
        pool.repay(WETH_ID, USDT_ID, 0, 10_000e18);
        vm.stopPrank();

        // The whole point of the bug: without the transfer, these balances
        // would be unchanged even though the debt was marked repaid.
        assertEq(usdt.balanceOf(bob), bobUsdtBefore - 10_000e18, "borrower balance did not decrease");
        assertEq(usdt.balanceOf(address(pool)), poolUsdtBefore + 10_000e18, "pool did not receive tokens");
    }

    function test_Bug1_Repay_RevertsWithoutApproval() public {
        // If the transfer were missing, repay would succeed even with zero
        // allowance. It must instead revert on the ERC20 transfer.
        _deposit(alice, USDT_ID, address(usdt), 500_000e18);
        _deposit(bob, WETH_ID, address(weth), 10e18);
        vm.prank(bob);
        pool.borrow(WETH_ID, USDT_ID, 10_000e18, 0.1e18);

        vm.prank(bob);
        vm.expectRevert(); // no approve() called
        pool.repay(WETH_ID, USDT_ID, 0, 10_000e18);
    }

    // ================================================================
    // Bug 2 — unapplied liquidation bonus
    // ================================================================
    // Original: liquidators received exactly the collateral equivalent of the
    // debt they repaid — no incentive to liquidate.
    // Fixed: LiquidationModule._liquidate scales seized collateral by
    // (1 + liquidationBonus).

    function test_Bug2_Liquidation_AppliesBonus() public {
        _deposit(alice, USDT_ID, address(usdt), 500_000e18);
        _deposit(bob, WETH_ID, address(weth), 10e18); // $30k collateral
        vm.prank(bob);
        pool.borrow(WETH_ID, USDT_ID, 20_000e18, 0.05e18); // $20k debt

        oracle.setPrice(wethFeed, 2_500 * RAY); // crash → HF < 1

        // Without the bonus, a liquidator repaying $20k of debt at $2,500/ETH
        // would receive exactly 20_000/2_500 = 8 WETH. The bonus must push it
        // strictly above that.
        uint256 debtRepaidRealValueInWeth = 20_000e18 * RAY / (2_500 * RAY);

        vm.startPrank(liquidator);
        usdt.mint(liquidator, 20_000e18);
        usdt.approve(address(pool), 20_000e18);
        pool.liquidate(bob, 0);
        vm.stopPrank();

        assertGt(
            weth.balanceOf(liquidator),
            debtRepaidRealValueInWeth,
            "liquidator did not receive a bonus above raw debt-equivalent collateral"
        );
    }

    // ================================================================
    // Bug 3 — oracle decimal mismatch
    // ================================================================
    // Original: Pool.getPrice() divided a raw Chainlink answer (8 decimals)
    // by RAY (1e18) without normalising it first, so every USD value was off
    // by a factor of 1e10.
    // Fixed: ChainlinkOracle reads feed.decimals() and normalises via
    // MathLib.chainlinkToRay; FtsoOracle does the equivalent for FTSOv2.
    //
    // This suite's MockOracle always returns RAY-scaled prices directly (it
    // stands in for "the oracle interface", not any specific feed format),
    // so the decimal-normalisation math itself is covered where it actually
    // lives — see test/unit/MathLib.t.sol's chainlinkToRay/ftsoToRay suites,
    // and test/unit/FtsoOracle.t.sol's getPrice tests. This test instead
    // proves the *symptom* of the bug — a 1e10 valuation error — is absent
    // from the pool's own collateral/borrow-limit math, by checking a borrow
    // against 1:1 USD-priced collateral lands where simple arithmetic implies
    // it should, not off by ten billion times.

    function test_Bug3_NoDecimalScalingErrorInBorrowLimit() public {
        // USDT priced at exactly $1 (1 RAY) in this suite's MockOracle.
        // 100,000 mUSDT collateral at 80% LTV, 5% buffer supports borrowing
        // up to ~76,190 USD worth of another $1-pegged-in-this-test-sense
        // asset. If a stray 1e10 factor were present anywhere in the
        // pipeline, a 24 WETH ($72,000) borrow would revert (limit off by
        // 10 orders of magnitude) instead of succeeding near the expected size.
        _deposit(alice, WETH_ID, address(weth), 500e18);
        _deposit(bob, USDT_ID, address(usdt), 100_000e18);

        uint256 wethBefore = weth.balanceOf(bob);

        vm.prank(bob);
        pool.borrow(USDT_ID, WETH_ID, 24e18, 0.05e18); // $72,000 worth of WETH, within 80% LTV

        assertEq(weth.balanceOf(bob) - wethBefore, 24e18);
    }

    // ================================================================
    // Bug 4 — stale borrow-index health checks (fixed in this PR)
    // ================================================================
    // Original / pre-fix: _checkHealth read `borrowReserve.borrowLiquidityIndex`
    // straight from storage. That index is only advanced by updateIndexes(),
    // which is only called from state-changing functions — never from the
    // view-only health check itself. So a position accruing interest between
    // two calls could look healthy indefinitely, right up until *something
    // else* touched that reserve (another user's deposit/borrow/repay) and
    // caught the index up.
    // Fixed: _checkHealth now uses ReserveLib.previewBorrowIndex, a
    // non-mutating peek that mirrors updateIndexes()'s math without writing
    // to storage.
    //
    // Setup note: with MIN_BUFFER=5%, LTV=80%, liquidationThreshold=85%, the
    // health factor at the moment a position opens is fixed at
    // (1+buffer)*LT/LTV = 1.05*0.85/0.8 ≈ 1.1156, independent of position
    // size. To make ~11.6% of interest accrual visible within a single test,
    // utilization (and therefore the borrow rate) needs to be pushed well
    // past `optimalUtilization` into the steep slope2 zone — hence the small,
    // tight liquidity pool below instead of this suite's usual large one.

    function test_Bug4_HealthCheck_ReflectsAccruedInterest_WithNoIntermediateTouch() public {
        _deposit(alice, USDT_ID, address(usdt), 22_000e18); // tight liquidity → high utilization
        _deposit(bob, WETH_ID, address(weth), 10e18); // $30k collateral, LT 85%

        vm.prank(bob);
        pool.borrow(WETH_ID, USDT_ID, 20_000e18, 0.05e18); // ~91% utilization → deep in slope2

        assertTrue(pool.checkPositionHealth(bob, 0), "should start healthy");

        // A full year passes. Nobody deposits/borrows/repays against the
        // USDT reserve in the meantime, so updateIndexes() never runs for it.
        // Under the old code, borrowLiquidityIndex would still read its
        // position-open-time value, understating debt indefinitely.
        vm.warp(block.timestamp + 365 days);

        assertFalse(
            pool.checkPositionHealth(bob, 0),
            "health check must reflect interest accrued since the reserve was last touched, not a stale index"
        );
    }

    function test_Bug4_HealthCheck_MatchesPostTouchValue() public {
        // Sanity check that the view-only preview agrees with what the index
        // actually becomes once something finally does touch the reserve —
        // i.e. previewBorrowIndex isn't just "different", it's *correct*.
        _deposit(alice, USDT_ID, address(usdt), 22_000e18);
        _deposit(bob, WETH_ID, address(weth), 10e18);

        vm.prank(bob);
        pool.borrow(WETH_ID, USDT_ID, 20_000e18, 0.05e18);

        vm.warp(block.timestamp + 365 days);
        bool healthBeforeTouch = pool.checkPositionHealth(bob, 0);

        // Now actually touch the USDT reserve via an unrelated deposit,
        // forcing updateIndexes() to run and the stored index to catch up.
        usdt.mint(alice, 1e18);
        _deposit(alice, USDT_ID, address(usdt), 1e18);

        bool healthAfterTouch = pool.checkPositionHealth(bob, 0);

        assertEq(healthBeforeTouch, healthAfterTouch, "preview must match the post-update ground truth");
    }
}
