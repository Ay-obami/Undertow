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

/// @title BorrowModule
/// @notice Handles borrow and repay.
abstract contract BorrowModule is PoolStorage {
    using SafeERC20 for IERC20;
    using TokenTransferLib for IERC20;
    using ReserveLib for DataTypes.ReserveData;
    using MathLib for uint256;

    // ================================================================
    // Borrow
    // ================================================================

    function _borrow(bytes32 collateralId, bytes32 borrowId, uint256 amount, uint256 bufferPercent) internal {
        require(amount > 0, "BorrowModule: zero amount");
        require(
            bufferPercent >= DataTypes.MIN_BUFFER && bufferPercent <= DataTypes.MAX_BUFFER,
            "BorrowModule: buffer out of range"
        );
        require(collateralId != borrowId, "BorrowModule: same asset");

        DataTypes.ReserveData storage collateralReserve = _getReserve(collateralId);
        DataTypes.ReserveData storage borrowReserve = _getReserve(borrowId);

        collateralReserve.assertActive();
        borrowReserve.assertActive();
        borrowReserve.assertBorrowable();

        // Update both reserves before any math
        _accrueReserve(collateralId);
        _accrueReserve(borrowId);

        borrowReserve.assertBorrowCap(amount);

        // USD values
        uint256 borrowPriceRay = IPriceOracle(_oracle).getPrice(borrowReserve.priceFeed);
        uint256 collateralPriceRay = IPriceOracle(_oracle).getPrice(collateralReserve.priceFeed);

        uint256 borrowValueRay = MathLib.rayMul(amount, borrowPriceRay);

        // Collateral required = borrowValue / collateralPrice * (1 + buffer) / ltv
        uint256 collateralRequired = MathLib.rayDiv(
            MathLib.rayMul(borrowValueRay, DataTypes.RAY + bufferPercent),
            MathLib.rayMul(collateralPriceRay, collateralReserve.ltv)
        );

        // Check utilization ceiling
        uint256 newUtil = MathLib.utilizationRate(borrowReserve.totalBorrows + amount, borrowReserve.totalDeposits);
        require(newUtil <= DataTypes.MAX_UTILIZATION, "BorrowModule: utilization ceiling");

        // Verify user has enough deposited collateral
        uint256 userCollateral =
            MathLib.toReal(_scaledDeposits[collateralId][msg.sender], collateralReserve.supplyLiquidityIndex);
        require(userCollateral >= collateralRequired, "BorrowModule: insufficient collateral");

        // Lock collateral by reducing the user's scaled deposit
        uint256 scaledLock = MathLib.toScaled(collateralRequired, collateralReserve.supplyLiquidityIndex);
        _scaledDeposits[collateralId][msg.sender] -= scaledLock;
        _totalScaledDeposits[collateralId] -= scaledLock;
        _totalLockedCollateral[collateralId] += collateralRequired;

        // Record scaled debt
        uint256 scaledDebt = MathLib.toScaled(amount, borrowReserve.borrowLiquidityIndex);
        _totalScaledDebt[borrowId] += scaledDebt;
        _syncReserveTotals(collateralId);
        _syncReserveTotals(borrowId);

        // Open position
        uint256 posId = _positions[msg.sender].length;
        _positions[msg.sender].push(
            DataTypes.Position({
                collateralReserveId: collateralId,
                borrowReserveId: borrowId,
                collateralPriceFeed: collateralReserve.priceFeed,
                borrowPriceFeed: borrowReserve.priceFeed,
                scaledDebt: scaledDebt,
                collateralLocked: collateralRequired,
                bufferPercent: bufferPercent,
                isOpen: true
            })
        );

        IERC20(borrowReserve.tokenAddress).safeTransfer(msg.sender, amount);

        emit Borrow(msg.sender, borrowId, collateralId, amount, collateralRequired, posId);
    }

    // ================================================================
    // Repay
    // ================================================================

    function _repay(bytes32 collateralId, bytes32 borrowId, uint256 positionId, uint256 repayAmount) internal {
        DataTypes.Position storage pos = _getPosition(msg.sender, positionId);
        require(pos.collateralReserveId == collateralId, "BorrowModule: wrong collateral");
        require(pos.borrowReserveId == borrowId, "BorrowModule: wrong borrow asset");

        DataTypes.ReserveData storage borrowReserve = _getReserve(borrowId);
        DataTypes.ReserveData storage collateralReserve = _getReserve(collateralId);

        _accrueReserve(borrowId);
        _accrueReserve(collateralId);

        uint256 currentDebt = MathLib.toReal(pos.scaledDebt, borrowReserve.borrowLiquidityIndex);
        uint256 actualRepay = repayAmount > currentDebt ? currentDebt : repayAmount;

        IERC20(borrowReserve.tokenAddress).pullExact(msg.sender, actualRepay);

        uint256 scaledDebtBefore = pos.scaledDebt;

        // Proportional collateral release
        uint256 collateralToReturn;
        if (actualRepay >= currentDebt) {
            // Full repay — return all locked collateral
            collateralToReturn = pos.collateralLocked;
            pos.isOpen = false;
            pos.scaledDebt = 0;
        } else {
            collateralToReturn = MathLib.rayMul(pos.collateralLocked, MathLib.rayDiv(actualRepay, currentDebt));
            // Reduce scaled debt proportionally
            pos.scaledDebt -= MathLib.toScaled(actualRepay, borrowReserve.borrowLiquidityIndex);
        }

        _totalScaledDebt[borrowId] -= scaledDebtBefore - pos.scaledDebt;
        _totalLockedCollateral[collateralId] -= collateralToReturn;
        pos.collateralLocked -= collateralToReturn;

        // Credit collateral back as a deposit
        uint256 scaledCollateral = MathLib.toScaled(collateralToReturn, collateralReserve.supplyLiquidityIndex);
        _scaledDeposits[collateralId][msg.sender] += scaledCollateral;
        _totalScaledDeposits[collateralId] += scaledCollateral;
        _syncReserveTotals(borrowId);
        _syncReserveTotals(collateralId);

        emit Repay(msg.sender, borrowId, collateralId, actualRepay, collateralToReturn, positionId);
    }

    // ================================================================
    // View
    // ================================================================

    function _getUserBorrowBalance(bytes32 reserveId, address user) internal view returns (uint256 total) {
        DataTypes.Position[] storage positions = _positions[user];
        DataTypes.ReserveData storage reserve = _reserves[reserveId];
        uint256 borrowIndex = reserve.previewBorrowIndex();
        uint256 len = positions.length;
        for (uint256 i; i < len; ++i) {
            if (!positions[i].isOpen) continue;
            if (positions[i].borrowReserveId != reserveId) continue;
            total += MathLib.toReal(positions[i].scaledDebt, borrowIndex);
        }
    }
}

