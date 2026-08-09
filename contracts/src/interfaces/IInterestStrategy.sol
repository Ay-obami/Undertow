// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title IInterestStrategy
/// @notice Pluggable interest rate strategy per reserve.
///         Decouples rate logic from the pool — different assets can use
///         different curves (stable-rate, variable, etc.) by swapping this.
interface IInterestStrategy {
    /// @notice Returns the current borrow rate (RAY-scaled, per-second annualised)
    function getBorrowRate(
        uint256 utilizationRate,
        uint256 slope1,
        uint256 slope2,
        uint256 baseRate,
        uint256 optimalUtilization
    ) external pure returns (uint256);

    /// @notice Returns the current supply rate (after reserve factor cut)
    function getSupplyRate(
        uint256 borrowRate,
        uint256 utilizationRate,
        uint256 reserveFactor
    ) external pure returns (uint256);

    /// @notice Compounds an index forward by `timeElapsed` seconds
    function computeUpdatedIndex(
        uint256 currentIndex,
        uint256 rate,
        uint256 timeElapsed
    ) external pure returns (uint256);
}
