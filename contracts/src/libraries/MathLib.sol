// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Math as OZMath} from "@openzeppelin/contracts/utils/math/Math.sol";
import {DataTypes} from "./DataTypes.sol";

/// @title MathLib
/// @notice Pure math helpers — RAY arithmetic, index compounding, health factor.
///         No storage reads. All functions are internal so they get inlined.
library MathLib {
    uint256 private constant RAY = DataTypes.RAY;
    uint256 private constant SECONDS_PER_YEAR = 365 days;

    // ================================================================
    // RAY arithmetic
    // ================================================================

    function rayMul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0 || b == 0) return 0;
        return (a * b + RAY / 2) / RAY; // rounded half-up
    }

    function rayDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b != 0, "MathLib: div by zero");
        return (a * RAY + b / 2) / b; // rounded half-up
    }

    // ================================================================
    // Index compounding  (linear approximation — same as original)
    // ================================================================

    /// @notice Compounds `currentIndex` forward by `timeElapsed` seconds at `rate`.
    /// @param  rate        Per-second annualised rate, RAY-scaled
    ///                     e.g. 5 % APY → 0.05e18 / SECONDS_PER_YEAR
    function compoundIndex(uint256 currentIndex, uint256 rate, uint256 timeElapsed) internal pure returns (uint256) {
        if (timeElapsed == 0) return currentIndex;
        uint256 linearAccumulator = RAY + (rate * timeElapsed) / SECONDS_PER_YEAR;
        return rayMul(currentIndex, linearAccumulator);
    }

    // ================================================================
    // Scaling helpers
    // ================================================================

    /// @notice Convert a raw amount to a scaled (principal) amount.
    ///         scaledAmount = amount / index
    function toScaled(uint256 amount, uint256 index) internal pure returns (uint256) {
        return rayDiv(amount, index);
    }

    /// @notice Floor-scaled credit or repayment, with full-precision intermediate multiplication.
    function toScaledDown(uint256 amount, uint256 index) internal pure returns (uint256) {
        require(index != 0, "MathLib: div by zero");
        return OZMath.mulDiv(amount, RAY, index);
    }

    /// @notice Ceiling-scaled outgoing claim burn or issued debt.
    function toScaledUp(uint256 amount, uint256 index) internal pure returns (uint256) {
        uint256 scaled = toScaledDown(amount, index);
        return scaled + (mulmod(amount, RAY, index) == 0 ? 0 : 1);
    }

    /// @notice Full-precision floor of a proportional amount.
    function mulDivDown(uint256 amount, uint256 numerator, uint256 denominator) internal pure returns (uint256) {
        require(denominator != 0, "MathLib: div by zero");
        return OZMath.mulDiv(amount, numerator, denominator);
    }

    /// @notice Reconstruct real balance from scaled principal and current index.
    ///         realAmount = scaledAmount * index
    function toReal(uint256 scaledAmount, uint256 index) internal pure returns (uint256) {
        return rayMul(scaledAmount, index);
    }

    // ================================================================
    // Health factor
    // ================================================================

    /// @notice Health factor of a position.
    ///         HF = (collateralValueUSD * liquidationThreshold) / debtValueUSD
    ///         HF >= 1e18  → healthy
    /// @param collateralValueRay  Collateral in USD, RAY-scaled
    /// @param debtValueRay        Debt in USD, RAY-scaled
    /// @param liquidationThreshold RAY-scaled (e.g. 0.85e18)
    function healthFactor(uint256 collateralValueRay, uint256 debtValueRay, uint256 liquidationThreshold)
        internal
        pure
        returns (uint256)
    {
        if (debtValueRay == 0) return type(uint256).max;
        return rayDiv(rayMul(collateralValueRay, liquidationThreshold), debtValueRay);
    }

    // ================================================================
    // Utilization
    // ================================================================

    /// @notice Utilization rate = totalBorrows / totalDeposits, RAY-scaled.
    function utilizationRate(uint256 totalBorrows, uint256 totalDeposits) internal pure returns (uint256) {
        if (totalDeposits == 0) return 0;
        return rayDiv(totalBorrows, totalDeposits);
    }

    // ================================================================
    // Price normalisation
    // ================================================================

    /// @notice Scale a Chainlink int256 price (8 decimals) to RAY (18 decimals).
    function chainlinkToRay(int256 price, uint8 decimals) internal pure returns (uint256) {
        require(price > 0, "MathLib: non-positive price");
        // multiply up to 18 decimals then express as RAY
        if (decimals >= 18) {
            return uint256(price) / (10 ** (decimals - 18));
        } else {
            return uint256(price) * (10 ** (18 - decimals));
        }
    }

    /// @notice Scale an FTSOv2 feed value (uint256 mantissa + int8 decimals) to RAY (18 decimals).
    /// @dev    FTSOv2 decimals are signed (int8) per the spec, but are positive for every
    ///         crypto feed observed in practice. Negative decimals are rejected explicitly
    ///         rather than silently mishandled.
    function ftsoToRay(uint256 value, int8 decimals) internal pure returns (uint256) {
        require(value > 0, "MathLib: non-positive price");
        require(decimals >= 0, "MathLib: negative feed decimals unsupported");
        uint8 dec = uint8(decimals);
        if (dec >= 18) {
            return value / (10 ** (dec - 18));
        } else {
            return value * (10 ** (18 - dec));
        }
    }
}

