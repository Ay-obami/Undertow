// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {DataTypes} from "../libraries/DataTypes.sol";
import {MathLib} from "../libraries/MathLib.sol";
import {ReserveLib} from "../libraries/ReserveLib.sol";
import {TokenTransferLib} from "../libraries/TokenTransferLib.sol";
import {PoolStorage} from "./PoolStorage.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title SupplyModule
/// @notice Handles deposit and withdraw.
///         Split from the monolithic Pool so each concern lives in its own file.
abstract contract SupplyModule is PoolStorage {
    using SafeERC20 for IERC20;
    using TokenTransferLib for IERC20;
    using ReserveLib for DataTypes.ReserveData;
    using MathLib for uint256;

    // ================================================================
    // Deposit
    // ================================================================

    function _deposit(bytes32 reserveId, uint256 amount) internal {
        require(amount > 0, "SupplyModule: zero amount");

        DataTypes.ReserveData storage reserve = _getReserve(reserveId);
        reserve.assertActive();
        _accrueReserve(reserveId); // accrue claims before checking the cap
        reserve.assertSupplyCap(amount);

        // Compute scaled deposit for this user
        uint256 scaled = MathLib.toScaledDown(amount, reserve.supplyLiquidityIndex);
        require(scaled > 0, "SupplyModule: amount below index precision");
        _scaledDeposits[reserveId][msg.sender] += scaled;

        _totalScaledDeposits[reserveId] += scaled;
        _syncReserveTotals(reserveId);

        IERC20(reserve.tokenAddress).pullExact(msg.sender, amount);

        emit Deposit(msg.sender, reserveId, amount, scaled);
    }

    // ================================================================
    // Withdraw
    // ================================================================

    function _withdraw(bytes32 reserveId, uint256 amount) internal {
        require(amount > 0, "SupplyModule: zero amount");

        DataTypes.ReserveData storage reserve = _getReserve(reserveId);
        reserve.assertActive();
        _accrueReserve(reserveId);

        uint256 userReal = MathLib.toReal(_scaledDeposits[reserveId][msg.sender], reserve.supplyLiquidityIndex);
        require(userReal >= amount, "SupplyModule: insufficient balance");

        uint256 scaledBurnt = amount == userReal
            ? _scaledDeposits[reserveId][msg.sender]
            : MathLib.toScaledUp(amount, reserve.supplyLiquidityIndex);
        _scaledDeposits[reserveId][msg.sender] -= scaledBurnt;

        _totalScaledDeposits[reserveId] -= scaledBurnt;
        _syncReserveTotals(reserveId);

        IERC20(reserve.tokenAddress).safeTransfer(msg.sender, amount);

        emit Withdraw(msg.sender, reserveId, amount, scaledBurnt);
    }

    // ================================================================
    // View
    // ================================================================

    /// @notice Current accrued deposit balance without updating reserve storage.
    function _getUserDepositBalance(bytes32 reserveId, address user) internal view returns (uint256) {
        DataTypes.ReserveData storage reserve = _reserves[reserveId];
        return MathLib.toReal(_scaledDeposits[reserveId][user], reserve.previewSupplyIndex());
    }
}

