// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {DataTypes} from "../libraries/DataTypes.sol";
import {MathLib} from "../libraries/MathLib.sol";
import {ReserveLib} from "../libraries/ReserveLib.sol";
import {TokenTransferLib} from "../libraries/TokenTransferLib.sol";
import {PoolStorage} from "./PoolStorage.sol";
import {IPriceOracle} from "../interfaces/IPriceOracle.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title LiquidationModule
/// @notice Handles liquidation of under-collateralised positions.
///
///         Bug fix vs original:
///           The original _liquidatePosition never applied liquidationBonus —
///           liquidators received exactly the collateral equivalent of debt with
///           no incentive. This module applies the bonus correctly:
///           collateralSeized = debtRepaidInCollateral * (1 + liquidationBonus)
abstract contract LiquidationModule is PoolStorage {
    using SafeERC20 for IERC20;
    using TokenTransferLib for IERC20;
    using ReserveLib for DataTypes.ReserveData;
    using MathLib for uint256;

    // ================================================================
    // Liquidate
    // ================================================================

    function _liquidate(address user, uint256 positionId) internal {
        require(user != address(0), "LiquidationModule: zero address");

        DataTypes.Position storage pos = _getPosition(user, positionId);

        DataTypes.ReserveData storage borrowReserve = _getReserve(pos.borrowReserveId);
        DataTypes.ReserveData storage collateralReserve = _getReserve(pos.collateralReserveId);

        borrowReserve.updateIndexes();
        collateralReserve.updateIndexes();

        // ── 1. Health check ──────────────────────────────────────────
        uint256 debtReal = MathLib.toReal(pos.scaledDebt, borrowReserve.borrowLiquidityIndex);

        uint256 borrowPrice = IPriceOracle(_oracle).getPrice(pos.borrowPriceFeed);
        uint256 collateralPrice = IPriceOracle(_oracle).getPrice(pos.collateralPriceFeed);

        uint256 debtValueRay = MathLib.rayMul(debtReal, borrowPrice);
        uint256 collateralValueRay = MathLib.rayMul(pos.collateralLocked, collateralPrice);

        uint256 hf = MathLib.healthFactor(collateralValueRay, debtValueRay, collateralReserve.liquidationThreshold);
        require(hf < DataTypes.RAY, "LiquidationModule: position healthy");

        // ── 2. Collateral to seize (with bonus) ──────────────────────
        //   debtRepaidInCollateralUnits = debtValueRay / collateralPrice
        //   seized = debtRepaidInCollateral * (1 + liquidationBonus)
        uint256 debtInCollateralUnits = MathLib.rayDiv(debtValueRay, collateralPrice);
        uint256 seized = MathLib.rayMul(
            debtInCollateralUnits,
            DataTypes.RAY + collateralReserve.liquidationBonus // BUG FIX: was ignored
        );

        // Cap at actual locked collateral
        if (seized > pos.collateralLocked) {
            seized = pos.collateralLocked;
        }

        // ── 3. Take full debt from liquidator ─────────────────────────
        IERC20(borrowReserve.tokenAddress).pullExact(msg.sender, debtReal);

        // ── 4. Close position ─────────────────────────────────────────
        borrowReserve.recordRepay(debtReal);
        pos.isOpen = false;

        // All locked collateral leaves the pool: seized plus borrower leftover.
        collateralReserve.recordWithdrawal(pos.collateralLocked);

        // ── 5. Transfer seized collateral to liquidator ───────────────
        IERC20(collateralReserve.tokenAddress).safeTransfer(msg.sender, seized);

        // ── 6. Return any leftover collateral (dust after bonus) ──────
        uint256 leftover = pos.collateralLocked - seized;
        if (leftover > 0) {
            IERC20(collateralReserve.tokenAddress).safeTransfer(user, leftover);
        }

        emit Liquidated(user, msg.sender, pos.collateralReserveId, pos.borrowReserveId, debtReal, seized, positionId);
    }

    // ================================================================
    // View
    // ================================================================

    /// @notice Returns true when HF >= 1 RAY (position is healthy).
    ///
    ///         Bug fix vs original: this used to read `borrowReserve.borrowLiquidityIndex`
    ///         directly, which can be stale (see `ReserveLib.previewBorrowIndex`) — a
    ///         position could look healthy here right up until someone else's deposit/
    ///         borrow/repay touched the reserve and caught it up. Now uses the
    ///         non-mutating preview so the health check always reflects real-time debt.
    function _checkHealth(address user, uint256 positionId) internal view returns (bool) {
        require(positionId < _positions[user].length, "invalid position");

        DataTypes.Position storage pos = _positions[user][positionId];

        if (!pos.isOpen) return false;

        DataTypes.ReserveData storage borrowReserve = _reserves[pos.borrowReserveId];
        DataTypes.ReserveData storage collateralReserve = _reserves[pos.collateralReserveId];

        uint256 debtReal = MathLib.toReal(pos.scaledDebt, borrowReserve.previewBorrowIndex());

        uint256 debtValueRay = MathLib.rayMul(debtReal, IPriceOracle(_oracle).getPrice(pos.borrowPriceFeed));

        uint256 collateralValueRay =
            MathLib.rayMul(pos.collateralLocked, IPriceOracle(_oracle).getPrice(pos.collateralPriceFeed));

        return
            MathLib.healthFactor(collateralValueRay, debtValueRay, collateralReserve.liquidationThreshold)
                >= DataTypes.RAY;
    }
}

