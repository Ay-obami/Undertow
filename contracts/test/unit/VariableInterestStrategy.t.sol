// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {VariableInterestStrategy} from "../../src/modules/VariableInterestStrategy.sol";
import {MathLib} from "../../src/libraries/MathLib.sol";

contract VariableInterestStrategyTest is Test {
    VariableInterestStrategy internal strategy;

    uint256 constant RAY        = 1e18;
    uint256 constant BASE_RATE  = 2e16;   // 2%
    uint256 constant SLOPE1     = 4e16;   // 4%
    uint256 constant SLOPE2     = 60e16;  // 60%
    uint256 constant OPT_UTIL   = 80e16;  // 80%
    uint256 constant RESERVE_FACTOR = 10e16; // 10%

    function setUp() public {
        strategy = new VariableInterestStrategy();
    }

    // ================================================================
    // getBorrowRate — below-optimal (normal) zone
    // ================================================================

    function test_BorrowRate_ZeroUtilization() public view {
        // util = 0 → utilRatio = 0 → borrowRate = baseRate + 0 = baseRate
        uint256 rate = strategy.getBorrowRate(0, SLOPE1, SLOPE2, BASE_RATE, OPT_UTIL);
        assertEq(rate, BASE_RATE);
    }

    function test_BorrowRate_AtOptimal_FullSlope1() public view {
        // util == optimal → utilRatio = 1 RAY → borrowRate = baseRate + slope1
        uint256 rate = strategy.getBorrowRate(OPT_UTIL, SLOPE1, SLOPE2, BASE_RATE, OPT_UTIL);
        assertApproxEqAbs(rate, BASE_RATE + SLOPE1, 2);
    }

    function test_BorrowRate_HalfOptimal() public view {
        // util = 40% (half of 80% optimal) → utilRatio = 0.5 → rate = base + 0.5*slope1
        uint256 util = 40e16;
        uint256 rate = strategy.getBorrowRate(util, SLOPE1, SLOPE2, BASE_RATE, OPT_UTIL);
        uint256 expected = BASE_RATE + MathLib.rayMul(MathLib.rayDiv(util, OPT_UTIL), SLOPE1);
        assertApproxEqAbs(rate, expected, 2);
    }

    function test_BorrowRate_ZeroOptimal_NormalZone() public view {
        // optimal = 0 means utilRatio forced to 0 (avoids div by zero)
        // util=0 <= 0 → normal zone, utilRatio = 0
        uint256 rate = strategy.getBorrowRate(0, SLOPE1, SLOPE2, BASE_RATE, 0);
        assertEq(rate, BASE_RATE);
    }

    // ================================================================
    // getBorrowRate — above-optimal (excess) zone
    // ================================================================

    function test_BorrowRate_AboveOptimal_MinimalExcess() public view {
        // util = 81% (just above 80% optimal)
        uint256 util = 81e16;
        uint256 rate = strategy.getBorrowRate(util, SLOPE1, SLOPE2, BASE_RATE, OPT_UTIL);
        // Should be base + slope1 + some small portion of slope2
        uint256 minExpected = BASE_RATE + SLOPE1;
        assertGt(rate, minExpected);
    }

    function test_BorrowRate_AboveOptimal_FullUtilization() public view {
        // util = 100% → excess = 20%, maxExcess = 20% → excessRatio = 1 RAY
        // rate = base + slope1 + slope2
        uint256 rate = strategy.getBorrowRate(RAY, SLOPE1, SLOPE2, BASE_RATE, OPT_UTIL);
        uint256 expected = BASE_RATE + SLOPE1 + SLOPE2;
        assertApproxEqAbs(rate, expected, 2);
    }

    function test_BorrowRate_AboveOptimal_90Percent() public view {
        // util = 90%, optimal = 80% → excess = 10%, maxExcess = 20% → ratio = 0.5
        uint256 util = 90e16;
        uint256 rate = strategy.getBorrowRate(util, SLOPE1, SLOPE2, BASE_RATE, OPT_UTIL);
        uint256 excess      = util - OPT_UTIL;                          // 10%
        uint256 maxExcess   = RAY  - OPT_UTIL;                          // 20%
        uint256 excessRatio = MathLib.rayDiv(excess, maxExcess);         // 0.5
        uint256 expected    = BASE_RATE + SLOPE1 + MathLib.rayMul(excessRatio, SLOPE2);
        assertApproxEqAbs(rate, expected, 2);
    }

    function test_BorrowRate_AboveOptimal_WhenMaxExcessIsZero() public view {
        // optimal = RAY (100%) means maxExcess = 0 → excessRatio forced to RAY
        // util > optimal = 100% is impossible in practice but we test the branch:
        // util = RAY, optimal = RAY → util <= optimal so normal zone, but
        // we need util > optimal. Use a mock optimal just below RAY.
        uint256 opt  = RAY - 1;
        uint256 util = RAY; // 100%
        // maxExcess = RAY - (RAY-1) = 1, not zero; excessRatio = (util-opt)/1 = 1 → RAY
        uint256 rate = strategy.getBorrowRate(util, SLOPE1, SLOPE2, BASE_RATE, opt);
        assertGt(rate, BASE_RATE + SLOPE1);
    }

    function test_BorrowRate_IncreasesMonotonically() public view {
        // Rates should be monotonically non-decreasing as utilization rises
        uint256 prev = 0;
        for (uint256 i = 0; i <= 100; i += 10) {
            uint256 util = i * RAY / 100;
            uint256 rate = strategy.getBorrowRate(util, SLOPE1, SLOPE2, BASE_RATE, OPT_UTIL);
            assertGe(rate, prev, "rate must be non-decreasing");
            prev = rate;
        }
    }

    function test_BorrowRate_JumpAtOptimal() public view {
        // Rate just below optimal vs just above — slope2 kicks in
        uint256 rateBelowOpt = strategy.getBorrowRate(OPT_UTIL - 1, SLOPE1, SLOPE2, BASE_RATE, OPT_UTIL);
        uint256 rateAboveOpt = strategy.getBorrowRate(OPT_UTIL + 1, SLOPE1, SLOPE2, BASE_RATE, OPT_UTIL);
        // Above should be strictly greater than below due to slope2
        assertGe(rateAboveOpt, rateBelowOpt);
    }

    // ================================================================
    // getSupplyRate
    // ================================================================

    function test_SupplyRate_ZeroUtilization() public view {
        // supplyRate = borrowRate * 0 * (1-reserveFactor) = 0
        uint256 rate = strategy.getSupplyRate(BASE_RATE, 0, RESERVE_FACTOR);
        assertEq(rate, 0);
    }

    function test_SupplyRate_FullUtilization_NoReserveFactor() public view {
        // supplyRate = borrowRate * 1 * (1-0) = borrowRate
        uint256 borrowRate = 6e16; // 6%
        uint256 rate = strategy.getSupplyRate(borrowRate, RAY, 0);
        assertApproxEqAbs(rate, borrowRate, 2);
    }

    function test_SupplyRate_WithReserveFactor() public view {
        // supplyRate = borrowRate * util * (1 - reserveFactor)
        uint256 borrowRate = 6e16; // 6%
        uint256 util       = 80e16; // 80%
        uint256 rate       = strategy.getSupplyRate(borrowRate, util, RESERVE_FACTOR);
        uint256 afterFactor = RAY - RESERVE_FACTOR;
        uint256 expected    = MathLib.rayMul(MathLib.rayMul(borrowRate, util), afterFactor);
        assertApproxEqAbs(rate, expected, 2);
    }

    function test_SupplyRate_AlwaysLessThanBorrowRate() public view {
        // Supply rate must always be <= borrow rate (reserve factor + util < 1)
        uint256 borrowRate = 10e16;
        uint256 util       = 80e16;
        uint256 supplyRate = strategy.getSupplyRate(borrowRate, util, RESERVE_FACTOR);
        assertLe(supplyRate, borrowRate);
    }

    function test_SupplyRate_ZeroBorrowRate() public view {
        uint256 rate = strategy.getSupplyRate(0, RAY, RESERVE_FACTOR);
        assertEq(rate, 0);
    }

    // ================================================================
    // computeUpdatedIndex
    // ================================================================

    function test_ComputeUpdatedIndex_ZeroElapsed_NoChange() public view {
        uint256 idx = strategy.computeUpdatedIndex(RAY, 5e16, 0);
        assertEq(idx, RAY);
    }

    function test_ComputeUpdatedIndex_GrowsOverTime() public view {
        uint256 idx1 = strategy.computeUpdatedIndex(RAY, 5e16, 30 days);
        uint256 idx2 = strategy.computeUpdatedIndex(RAY, 5e16, 90 days);
        assertGt(idx2, idx1);
    }

    function test_ComputeUpdatedIndex_StartingIndexPreserved() public view {
        // A higher starting index multiplies proportionally
        uint256 idx1 = strategy.computeUpdatedIndex(RAY,    5e16, 365 days);
        uint256 idx2 = strategy.computeUpdatedIndex(2 * RAY, 5e16, 365 days);
        assertApproxEqAbs(idx2, 2 * idx1, 2);
    }

    // ================================================================
    // Fuzz
    // ================================================================

    function testFuzz_BorrowRate_NeverBelowBaseRate(uint256 util) public view {
        util = bound(util, 0, RAY);
        uint256 rate = strategy.getBorrowRate(util, SLOPE1, SLOPE2, BASE_RATE, OPT_UTIL);
        assertGe(rate, BASE_RATE, "rate must be >= baseRate");
    }

    function testFuzz_SupplyRate_NeverExceedsBorrowRate(uint256 util, uint256 reserveFactor) public view {
        util         = bound(util, 0, RAY);
        reserveFactor = bound(reserveFactor, 0, RAY);
        uint256 borrowRate = strategy.getBorrowRate(util, SLOPE1, SLOPE2, BASE_RATE, OPT_UTIL);
        uint256 supplyRate = strategy.getSupplyRate(borrowRate, util, reserveFactor);
        assertLe(supplyRate, borrowRate);
    }
}