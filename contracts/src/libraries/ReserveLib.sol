// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {DataTypes} from "./DataTypes.sol";
import {MathLib} from "./MathLib.sol";
import {IInterestStrategy} from "../interfaces/IInterestStrategy.sol";

/// @title ReserveLib
/// @notice Helpers for updating and previewing reserve accounting.
///         Pool modules import this so the accounting logic is not duplicated.
library ReserveLib {
    using MathLib for uint256;

    // ================================================================
    // Index update
    // ================================================================

    /// @notice Bring both liquidity indexes forward to `block.timestamp`.
    ///         Must be called at the start of every state-changing operation.
    function updateIndexes(DataTypes.ReserveData storage reserve) internal {
        uint256 elapsed = block.timestamp - reserve.lastUpdateTimestamp;
        if (elapsed == 0) return;

        uint256 util = MathLib.utilizationRate(reserve.totalBorrows, reserve.totalDeposits);

        uint256 borrowRate = IInterestStrategy(reserve.interestStrategy)
            .getBorrowRate(util, reserve.slope1, reserve.slope2, reserve.baseInterestRate, reserve.optimalUtilization);

        uint256 supplyRate =
            IInterestStrategy(reserve.interestStrategy).getSupplyRate(borrowRate, util, reserve.reserveFactor);

        reserve.borrowLiquidityIndex = MathLib.compoundIndex(reserve.borrowLiquidityIndex, borrowRate, elapsed);

        reserve.supplyLiquidityIndex = MathLib.compoundIndex(reserve.supplyLiquidityIndex, supplyRate, elapsed);

        reserve.lastUpdateTimestamp = block.timestamp;
    }

    /// @notice Non-mutating "peek" at the borrow index as of `block.timestamp`.
    /// @dev    Bug fix: `_checkHealth` (and any other `view` caller) cannot call
    ///         `updateIndexes` — it mutates storage. Reading `reserve.borrowLiquidityIndex`
    ///         directly instead reads whatever it was as of the reserve's last
    ///         state-changing interaction, understating accrued interest for every
    ///         second since then. A position can accrue enough interest to become
    ///         unhealthy while every view call still reports the old, smaller debt,
    ///         letting it dodge liquidation until someone happens to touch the
    ///         reserve. This mirrors `updateIndexes`'s borrow-side math exactly,
    ///         without writing to storage, so health checks always see the true
    ///         current debt.
    function previewBorrowIndex(DataTypes.ReserveData storage reserve) internal view returns (uint256) {
        uint256 elapsed = block.timestamp - reserve.lastUpdateTimestamp;
        if (elapsed == 0) return reserve.borrowLiquidityIndex;

        uint256 util = MathLib.utilizationRate(reserve.totalBorrows, reserve.totalDeposits);

        uint256 borrowRate = IInterestStrategy(reserve.interestStrategy)
            .getBorrowRate(util, reserve.slope1, reserve.slope2, reserve.baseInterestRate, reserve.optimalUtilization);

        return MathLib.compoundIndex(reserve.borrowLiquidityIndex, borrowRate, elapsed);
    }

    /// @notice Preview accrued supply interest using the same rates as updateIndexes.
    function previewSupplyIndex(DataTypes.ReserveData storage reserve) internal view returns (uint256) {
        uint256 elapsed = block.timestamp - reserve.lastUpdateTimestamp;
        if (elapsed == 0) return reserve.supplyLiquidityIndex;

        uint256 util = MathLib.utilizationRate(reserve.totalBorrows, reserve.totalDeposits);
        uint256 borrowRate = IInterestStrategy(reserve.interestStrategy)
            .getBorrowRate(util, reserve.slope1, reserve.slope2, reserve.baseInterestRate, reserve.optimalUtilization);
        uint256 supplyRate =
            IInterestStrategy(reserve.interestStrategy).getSupplyRate(borrowRate, util, reserve.reserveFactor);
        return MathLib.compoundIndex(reserve.supplyLiquidityIndex, supplyRate, elapsed);
    }

    // ================================================================
    // Scaled accounting
    // ================================================================

    /// @notice Add a deposit: update totalDeposits with real amount.
    function recordDeposit(DataTypes.ReserveData storage reserve, uint256 amount) internal {
        reserve.totalDeposits += amount;
    }

    /// @notice Remove a withdrawal from totalDeposits.
    function recordWithdrawal(DataTypes.ReserveData storage reserve, uint256 amount) internal {
        require(reserve.totalDeposits >= amount, "ReserveLib: insufficient deposits");
        reserve.totalDeposits -= amount;
    }

    /// @notice Increase totalBorrows by real borrow amount.
    function recordBorrow(DataTypes.ReserveData storage reserve, uint256 amount) internal {
        reserve.totalBorrows += amount;
    }

    /// @notice Decrease totalBorrows by real repay amount.
    function recordRepay(DataTypes.ReserveData storage reserve, uint256 amount) internal {
        if (amount > reserve.totalBorrows) {
            reserve.totalBorrows = 0;
        } else {
            reserve.totalBorrows -= amount;
        }
    }

    // ================================================================
    // Validation helpers
    // ================================================================

    function assertActive(DataTypes.ReserveData storage reserve) internal view {
        require(reserve.isActive, "ReserveLib: reserve inactive");
    }

    function assertBorrowable(DataTypes.ReserveData storage reserve) internal view {
        require(reserve.isBorrowable, "ReserveLib: reserve not borrowable");
    }

    function assertSupplyCap(DataTypes.ReserveData storage reserve, uint256 extra) internal view {
        require(reserve.totalDeposits + extra <= reserve.supplyCap, "ReserveLib: supply cap exceeded");
    }

    function assertBorrowCap(DataTypes.ReserveData storage reserve, uint256 extra) internal view {
        require(reserve.totalBorrows + extra <= reserve.borrowCap, "ReserveLib: borrow cap exceeded");
    }
}

