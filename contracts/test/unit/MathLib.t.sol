// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {MathLib} from "../../src/libraries/MathLib.sol";

/// @notice Exposes internal MathLib functions for direct testing.
///         Libraries with internal functions get inlined, so we wrap them.
contract MathLibHarness {
    function rayMul(uint256 a, uint256 b) external pure returns (uint256) {
        return MathLib.rayMul(a, b);
    }

    function rayDiv(uint256 a, uint256 b) external pure returns (uint256) {
        return MathLib.rayDiv(a, b);
    }

    function compoundIndex(uint256 currentIndex, uint256 rate, uint256 timeElapsed) external pure returns (uint256) {
        return MathLib.compoundIndex(currentIndex, rate, timeElapsed);
    }

    function toScaled(uint256 amount, uint256 index) external pure returns (uint256) {
        return MathLib.toScaled(amount, index);
    }

    function toReal(uint256 scaledAmount, uint256 index) external pure returns (uint256) {
        return MathLib.toReal(scaledAmount, index);
    }

    function healthFactor(uint256 collateralValueRay, uint256 debtValueRay, uint256 liquidationThreshold)
        external
        pure
        returns (uint256)
    {
        return MathLib.healthFactor(collateralValueRay, debtValueRay, liquidationThreshold);
    }

    function utilizationRate(uint256 totalBorrows, uint256 totalDeposits) external pure returns (uint256) {
        return MathLib.utilizationRate(totalBorrows, totalDeposits);
    }

    function chainlinkToRay(int256 price, uint8 decimals) external pure returns (uint256) {
        return MathLib.chainlinkToRay(price, decimals);
    }

    function ftsoToRay(uint256 value, int8 decimals) external pure returns (uint256) {
        return MathLib.ftsoToRay(value, decimals);
    }
}

contract MathLibTest is Test {
    MathLibHarness internal lib;
    uint256 constant RAY = 1e18;

    function setUp() public {
        lib = new MathLibHarness();
    }

    // ================================================================
    // rayMul
    // ================================================================

    function test_RayMul_ZeroA() public view {
        assertEq(lib.rayMul(0, 5e18), 0);
    }

    function test_RayMul_ZeroB() public view {
        assertEq(lib.rayMul(5e18, 0), 0);
    }

    function test_RayMul_BothZero() public view {
        assertEq(lib.rayMul(0, 0), 0);
    }

    function test_RayMul_Identity() public view {
        // a * RAY = a
        assertEq(lib.rayMul(123e18, RAY), 123e18);
    }

    function test_RayMul_HalfRay() public view {
        // 2e18 * 0.5e18 = 1e18
        assertEq(lib.rayMul(2e18, 0.5e18), 1e18);
    }

    function test_RayMul_RoundingHalfUp() public view {
        // Should round half-up
        // (RAY/2 + RAY/2) / RAY should be 1, but let's test a case at boundary
        uint256 result = lib.rayMul(1, RAY / 2 + 1);
        // 1 * (RAY/2+1) + RAY/2 = RAY + 1 → div RAY = 1
        assertEq(result, 1);
    }

    // ================================================================
    // rayDiv
    // ================================================================

    function test_RayDiv_DivByZeroReverts() public {
        vm.expectRevert("MathLib: div by zero");
        lib.rayDiv(1e18, 0);
    }

    function test_RayDiv_Identity() public view {
        // a / RAY = a (when a is already RAY-scaled)
        assertEq(lib.rayDiv(1e18, RAY), 1e18);
    }

    function test_RayDiv_HalvesValue() public view {
        // 1e18 / 2e18 = 0.5e18
        assertEq(lib.rayDiv(1e18, 2e18), 0.5e18);
    }

    function test_RayDiv_RoundingHalfUp() public view {
        // Check that rounding is half-up not truncation
        // 3 / 2 → (3 * RAY + 1) / 2 = should round
        uint256 result = lib.rayDiv(3, 2);
        // 3 * 1e18 + 1 = 3000000000000000001, div 2 = 1500000000000000000 (exact)
        assertEq(result, 1500000000000000000);
    }

    // ================================================================
    // compoundIndex
    // ================================================================

    function test_CompoundIndex_ZeroTimeReturnsCurrentIndex() public view {
        uint256 idx = lib.compoundIndex(1e18, 5e16, 0); // 0 seconds elapsed
        assertEq(idx, 1e18);
    }

    function test_CompoundIndex_OneYear_FivePercent() public view {
        // 5% APY for one year starting at RAY
        uint256 rate = 5e16; // 0.05e18
        uint256 elapsed = 365 days;
        uint256 result = lib.compoundIndex(RAY, rate, elapsed);
        // linearAccumulator = RAY + (rate * elapsed) / SECONDS_PER_YEAR
        // = 1e18 + (5e16 * 365 days) / 365 days = 1e18 + 5e16 = 1.05e18
        // rayMul(1e18, 1.05e18) = 1.05e18
        assertApproxEqAbs(result, 1.05e18, 1e10);
    }

    function test_CompoundIndex_ZeroRate() public view {
        uint256 result = lib.compoundIndex(1e18, 0, 365 days);
        // linearAccumulator = RAY + 0 = RAY → rayMul(RAY, RAY) = RAY
        assertEq(result, 1e18);
    }

    function test_CompoundIndex_GrowsWithTime() public view {
        uint256 r1 = lib.compoundIndex(1e18, 5e16, 30 days);
        uint256 r2 = lib.compoundIndex(1e18, 5e16, 60 days);
        assertGt(r2, r1);
    }

    // ================================================================
    // toScaled / toReal
    // ================================================================

    function test_ToScaled_AtRayIndex() public view {
        // scaledAmount = amount / RAY = amount (when index = RAY)
        assertEq(lib.toScaled(500e18, RAY), 500e18);
    }

    function test_ToReal_AtRayIndex() public view {
        assertEq(lib.toReal(500e18, RAY), 500e18);
    }

    function test_ToScaled_ToReal_Roundtrip() public view {
        uint256 amount = 1234e18;
        uint256 index = 1.05e18;
        uint256 scaled = lib.toScaled(amount, index);
        uint256 real = lib.toReal(scaled, index);
        // Small rounding error from integer division is acceptable
        assertApproxEqAbs(real, amount, 2);
    }

    function test_ToReal_HigherIndexGrowsBalance() public view {
        uint256 scaled = lib.toScaled(1000e18, RAY);
        uint256 balAfter = lib.toReal(scaled, 1.1e18);
        assertGt(balAfter, 1000e18);
    }

    // ================================================================
    // healthFactor
    // ================================================================

    function test_HealthFactor_ZeroDebtReturnsMaxUint() public view {
        uint256 hf = lib.healthFactor(1000e18, 0, 0.85e18);
        assertEq(hf, type(uint256).max);
    }

    function test_HealthFactor_HealthyPosition() public view {
        // collateral=$100, debt=$50, threshold=85%
        // HF = (100 * 0.85) / 50 = 1.7 → > 1 RAY
        uint256 hf = lib.healthFactor(100e18, 50e18, 0.85e18);
        assertGt(hf, RAY);
    }

    function test_HealthFactor_UnhealthyPosition() public view {
        // collateral=$50, debt=$100, threshold=85%
        // HF = (50 * 0.85) / 100 = 0.425 → < 1 RAY
        uint256 hf = lib.healthFactor(50e18, 100e18, 0.85e18);
        assertLt(hf, RAY);
    }

    function test_HealthFactor_ExactlyOne() public view {
        // collateral=100, debt=85, threshold=85% → HF = (100*0.85)/85 = 1.0
        uint256 hf = lib.healthFactor(100e18, 85e18, 0.85e18);
        assertApproxEqAbs(hf, RAY, 2);
    }

    // ================================================================
    // utilizationRate
    // ================================================================

    function test_UtilizationRate_ZeroDepositsReturnsZero() public view {
        // No deposits → 0 (avoids div by zero)
        assertEq(lib.utilizationRate(0, 0), 0);
    }

    function test_UtilizationRate_ZeroBorrows() public view {
        assertEq(lib.utilizationRate(0, 1000e18), 0);
    }

    function test_UtilizationRate_FullUtilization() public view {
        // borrows = deposits → 100%
        uint256 util = lib.utilizationRate(1000e18, 1000e18);
        assertEq(util, RAY);
    }

    function test_UtilizationRate_HalfUtilization() public view {
        uint256 util = lib.utilizationRate(500e18, 1000e18);
        assertEq(util, 0.5e18);
    }

    function test_UtilizationRate_80Percent() public view {
        uint256 util = lib.utilizationRate(800e18, 1000e18);
        assertApproxEqAbs(util, 0.8e18, 2);
    }

    // ================================================================
    // chainlinkToRay
    // ================================================================

    function test_ChainlinkToRay_RejectsZeroPrice() public {
        vm.expectRevert("MathLib: non-positive price");
        lib.chainlinkToRay(0, 8);
    }

    function test_ChainlinkToRay_RejectsNegativePrice() public {
        vm.expectRevert("MathLib: non-positive price");
        lib.chainlinkToRay(-1, 8);
    }

    function test_ChainlinkToRay_EightDecimals() public view {
        // Chainlink price 100000000 (=$1.00 with 8 decimals) → 1e18
        int256 price = 100_000_000; // 1.00 USD, 8 decimals
        uint256 ray = lib.chainlinkToRay(price, 8);
        assertEq(ray, 1e18);
    }

    function test_ChainlinkToRay_EightDecimals_3000USD() public view {
        // $3000 with 8 decimals = 300_000_000_000
        int256 price = 300_000_000_000;
        uint256 ray = lib.chainlinkToRay(price, 8);
        assertEq(ray, 3_000e18);
    }

    function test_ChainlinkToRay_18Decimals_SameValue() public view {
        // 18 decimals: price == RAY-scaled already
        int256 price = 1e18; // $1 with 18 decimals
        uint256 ray = lib.chainlinkToRay(price, 18);
        assertEq(ray, 1e18);
    }

    function test_ChainlinkToRay_MoreThan18Decimals_Divides() public view {
        // decimals >= 18 branch: divide
        // price = 1e20 with 20 decimals → $1 → 1e18
        int256 price = 1e20;
        uint256 ray = lib.chainlinkToRay(price, 20);
        assertEq(ray, 1e18);
    }

    function test_ChainlinkToRay_SixDecimals() public view {
        // 6 decimals (USDC style): price = 1_000_000 = $1
        int256 price = 1_000_000;
        uint256 ray = lib.chainlinkToRay(price, 6);
        assertEq(ray, 1e18);
    }

    function test_ChainlinkToRay_ZeroDecimals() public view {
        // 0 decimals: price = 1 = $1 → multiply by 1e18
        int256 price = 1;
        uint256 ray = lib.chainlinkToRay(price, 0);
        assertEq(ray, 1e18);
    }

    // ================================================================
    // ftsoToRay
    // ================================================================

    function test_FtsoToRay_RejectsZeroValue() public {
        vm.expectRevert("MathLib: non-positive price");
        lib.ftsoToRay(0, 5);
    }

    function test_FtsoToRay_RejectsNegativeDecimals() public {
        vm.expectRevert("MathLib: negative feed decimals unsupported");
        lib.ftsoToRay(315000, -1);
    }

    function test_FtsoToRay_FiveDecimals_TypicalFtsoFeed() public view {
        // XRP/USD = $3.15 with 5 decimals (FTSOv2's typical crypto feed precision)
        uint256 ray = lib.ftsoToRay(315_000, 5);
        assertEq(ray, 3.15e18);
    }

    function test_FtsoToRay_EighteenDecimals_SameValue() public view {
        uint256 ray = lib.ftsoToRay(1e18, 18);
        assertEq(ray, 1e18);
    }

    function test_FtsoToRay_MoreThan18Decimals_Divides() public view {
        uint256 ray = lib.ftsoToRay(1e20, 20);
        assertEq(ray, 1e18);
    }

    function test_FtsoToRay_ZeroDecimals() public view {
        uint256 ray = lib.ftsoToRay(1, 0);
        assertEq(ray, 1e18);
    }

    function test_FtsoToRay_MatchesChainlinkToRay_ForEquivalentInputs() public view {
        // Same mantissa/decimals interpreted through either path should agree,
        // since both are just base-10 rescale to RAY.
        uint256 ftso = lib.ftsoToRay(300_000_000_000, 8);
        uint256 chainlink = lib.chainlinkToRay(300_000_000_000, 8);
        assertEq(ftso, chainlink);
    }
}
