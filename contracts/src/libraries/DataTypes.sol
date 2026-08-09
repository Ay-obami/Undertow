// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title DataTypes
/// @notice Central struct & constant definitions shared across all modules.
///         No logic lives here — only data shapes.
library DataTypes {
    // ================================================================
    // Constants
    // ================================================================

    uint256 internal constant RAY = 1e18;
    uint256 internal constant MIN_BUFFER = 0.05e18; // 5 %
    uint256 internal constant MAX_BUFFER = 1e18;    // 100 %
    uint256 internal constant MAX_UTILIZATION = 0.95e18; // 95 %

    // ================================================================
    // Reserve
    // ================================================================

    /// @notice Configuration provided when a reserve is first added.
    ///         Separated from runtime state to keep addReserve() readable.
    struct ReserveConfig {
        string name;
        address tokenAddress;
        address priceFeed;
        address interestStrategy; // IInterestStrategy implementation
        uint256 liquidationThreshold; // RAY-scaled (e.g. 0.85e18 = 85 %)
        uint256 ltv;                  // must be < liquidationThreshold
        uint256 slope1;
        uint256 slope2;
        uint256 baseInterestRate;
        uint256 optimalUtilization;
        uint256 liquidationBonus;     // RAY-scaled bonus on top of debt repaid
        uint256 reserveFactor;        // fraction of interest kept by protocol
        uint256 borrowCap;            // max total borrows (token units)
        uint256 supplyCap;            // max total deposits (token units)
        bool isActive;
        bool isBorrowable;
    }

    /// @notice Runtime state of a reserve — mutated on every deposit/borrow/repay.
    struct ReserveData {
        // --- identification ---
        bytes32 id;          // keccak256(name) — immutable after init
        string  name;        // human-readable label
        // --- token & feed ---
        address tokenAddress;
        address priceFeed;
        address interestStrategy;
        // --- risk params (set at init, adjustable by owner) ---
        uint256 liquidationThreshold;
        uint256 ltv;
        uint256 slope1;
        uint256 slope2;
        uint256 baseInterestRate;
        uint256 optimalUtilization;
        uint256 liquidationBonus;
        uint256 reserveFactor;
        uint256 borrowCap;
        uint256 supplyCap;
        // --- accounting (mutated each block) ---
        uint256 totalDeposits;
        uint256 totalBorrows;
        uint256 supplyLiquidityIndex;  // RAY-scaled, starts at 1e18
        uint256 borrowLiquidityIndex;  // RAY-scaled, starts at 1e18
        uint256 lastUpdateTimestamp;
        // --- flags ---
        bool isActive;
        bool isBorrowable;
    }

    // ================================================================
    // Position
    // ================================================================

    /// @notice A single collateral ↔ borrow pair opened by a user.
    struct Position {
        bytes32 collateralReserveId;
        bytes32 borrowReserveId;
        address collateralPriceFeed; // cached at open — oracle address
        address borrowPriceFeed;     // cached at open
        uint256 scaledDebt;          // debt / borrowLiquidityIndex at open time
        uint256 collateralLocked;    // raw token units locked
        uint256 bufferPercent;       // extra collateral the user chose to lock
        bool    isOpen;              // false after repay/liquidate (avoids gaps)
    }
}
