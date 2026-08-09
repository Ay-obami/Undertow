// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IInterestStrategy} from "../interfaces/IInterestStrategy.sol";
import {MathLib} from "../libraries/MathLib.sol";
import {DataTypes} from "../libraries/DataTypes.sol";

/// @title VariableInterestStrategy
/// @notice Two-slope variable rate model (identical math to the original
///         InterestCalculator pair, unified into a single stateless contract).
///
///         Borrow rate:
///           if util <= optimal  →  baseRate + (util / optimal) * slope1
///           else                →  baseRate + slope1 + ((util - optimal) / (1 - optimal)) * slope2
///
///         Supply rate:
///           borrowRate * util * (1 - reserveFactor)
///
/// @dev    Deploy once; every reserve references this address via ReserveConfig.
contract VariableInterestStrategy is IInterestStrategy {
    using MathLib for uint256;

    uint256 private constant RAY = DataTypes.RAY;

    // ================================================================
    // IInterestStrategy
    // ================================================================

    function getBorrowRate(
        uint256 utilizationRate,
        uint256 slope1,
        uint256 slope2,
        uint256 baseRate,
        uint256 optimalUtilization
    ) external pure override returns (uint256) {
        return _borrowRate(utilizationRate, slope1, slope2, baseRate, optimalUtilization);
    }

    function getSupplyRate(
        uint256 borrowRate,
        uint256 utilizationRate,
        uint256 reserveFactor
    ) external pure override returns (uint256) {
        // supplyRate = borrowRate * utilization * (1 - reserveFactor)
        uint256 afterFactor = RAY - reserveFactor;
        return MathLib.rayMul(MathLib.rayMul(borrowRate, utilizationRate), afterFactor);
    }

    function computeUpdatedIndex(
        uint256 currentIndex,
        uint256 rate,
        uint256 timeElapsed
    ) external pure override returns (uint256) {
        return MathLib.compoundIndex(currentIndex, rate, timeElapsed);
    }

    // ================================================================
    // Internal
    // ================================================================

    function _borrowRate(
        uint256 util,
        uint256 slope1,
        uint256 slope2,
        uint256 baseRate,
        uint256 optimal
    ) private pure returns (uint256) {
        if (util <= optimal) {
            // Normal zone: linear up to slope1
            uint256 utilRatio = optimal == 0 ? 0 : MathLib.rayDiv(util, optimal);
            return baseRate + MathLib.rayMul(utilRatio, slope1);
        } else {
            // Excess zone: slope1 fully applied + steep slope2 portion
            uint256 excess = util - optimal;
            uint256 maxExcess = RAY - optimal; // can't exceed 1 - optimal
            uint256 excessRatio = maxExcess == 0 ? RAY : MathLib.rayDiv(excess, maxExcess);
            return baseRate + slope1 + MathLib.rayMul(excessRatio, slope2);
        }
    }
}
