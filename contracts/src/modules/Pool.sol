// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {DataTypes} from "../libraries/DataTypes.sol";
import {MathLib} from "../libraries/MathLib.sol";
import {ReserveLib} from "../libraries/ReserveLib.sol";
import {PoolStorage} from "./PoolStorage.sol";
import {SupplyModule} from "./SupplyModule.sol";
import {BorrowModule} from "./BorrowModule.sol";
import {LiquidationModule} from "./LiquidationModule.sol";

/// @title Pool
/// @notice Thin facade that composes SupplyModule, BorrowModule, and
///         LiquidationModule into the single IPool contract surface.
///
///         All business logic lives in the modules. Pool only:
///           • routes external calls to the right module
///           • owns reserve administration (addReserve / setActive…)
///           • exposes view functions
///
///         Inheritance order (MRO right-to-left):
///         Pool → LiquidationModule → BorrowModule → SupplyModule → PoolStorage → IPool
contract Pool is SupplyModule, BorrowModule, LiquidationModule {
    using ReserveLib for DataTypes.ReserveData;
    using MathLib for uint256;

    // ================================================================
    // Constructor
    // ================================================================

    constructor(address oracle) {
        require(oracle != address(0), "Pool: zero oracle");
        _oracle = oracle;
        _owner  = msg.sender;
    }

    // ================================================================
    // IPool — core user actions
    // ================================================================

    /// test
    function deposit(bytes32 reserveId, uint256 amount) external override {
        _deposit(reserveId, amount);
    }

    function withdraw(bytes32 reserveId, uint256 amount) external override {
        _withdraw(reserveId, amount);
    }

    function borrow(
        bytes32 collateralId,
        bytes32 borrowId,
        uint256 amount,
        uint256 bufferPercent
    ) external override {
        _borrow(collateralId, borrowId, amount, bufferPercent);
    }

    function repay(
        bytes32 collateralId,
        bytes32 borrowId,
        uint256 positionId,
        uint256 repayAmount
    ) external override {
        _repay(collateralId, borrowId, positionId, repayAmount);
    }

    function liquidate(address user, uint256 positionId) external override {
        _liquidate(user, positionId);
    }

    // ================================================================
    // IPool — admin
    // ================================================================

    function addReserve(DataTypes.ReserveConfig calldata cfg) external override onlyOwner {
        bytes32 id = getReserveId(cfg.name);
        require(_reserves[id].tokenAddress == address(0), "Pool: reserve exists");
        require(cfg.tokenAddress      != address(0), "Pool: zero token");
        require(cfg.priceFeed         != address(0), "Pool: zero feed");
        require(cfg.interestStrategy  != address(0), "Pool: zero strategy");
        require(cfg.ltv < cfg.liquidationThreshold,  "Pool: ltv >= threshold");

        DataTypes.ReserveData storage r = _reserves[id];
        r.id                   = id;
        r.name                 = cfg.name;
        r.tokenAddress         = cfg.tokenAddress;
        r.priceFeed            = cfg.priceFeed;
        r.interestStrategy     = cfg.interestStrategy;
        r.liquidationThreshold = cfg.liquidationThreshold;
        r.ltv                  = cfg.ltv;
        r.slope1               = cfg.slope1;
        r.slope2               = cfg.slope2;
        r.baseInterestRate     = cfg.baseInterestRate;
        r.optimalUtilization   = cfg.optimalUtilization;
        r.liquidationBonus     = cfg.liquidationBonus;
        r.reserveFactor        = cfg.reserveFactor;
        r.borrowCap            = cfg.borrowCap;
        r.supplyCap            = cfg.supplyCap;
        r.isActive             = cfg.isActive;
        r.isBorrowable         = cfg.isBorrowable;
        // Index starts at RAY (1.0)
        r.supplyLiquidityIndex = DataTypes.RAY;
        r.borrowLiquidityIndex = DataTypes.RAY;
        r.lastUpdateTimestamp  = block.timestamp;

        _reserveIds.push(id);

        emit ReserveInitialized(
            id,
            cfg.name,
            cfg.tokenAddress,
            cfg.priceFeed,
            cfg.ltv,
            cfg.liquidationThreshold
        );
    }

    function setReserveActive(bytes32 reserveId, bool active) external override onlyOwner {
        _getReserve(reserveId).isActive = active;
        emit ReserveStatusUpdated(reserveId, active);
    }

    function setReserveBorrowable(bytes32 reserveId, bool borrowable) external override onlyOwner {
        _getReserve(reserveId).isBorrowable = borrowable;
        emit ReserveBorrowStatusUpdated(reserveId, borrowable);
    }

    // ================================================================
    // IPool — views
    // ================================================================

    function getReserve(bytes32 reserveId) external view override returns (DataTypes.ReserveData memory) {
        return _getReserve(reserveId);
    }

    function getAllReserves() external view override returns (DataTypes.ReserveData[] memory) {
        uint256 len = _reserveIds.length;
        DataTypes.ReserveData[] memory result = new DataTypes.ReserveData[](len);
        for (uint256 i; i < len; ++i) {
            result[i] = _reserves[_reserveIds[i]];
        }
        return result;
    }

    function getReserveId(string calldata name) public pure override returns (bytes32) {
        return keccak256(abi.encodePacked(name));
    }

    function getUserDepositBalance(bytes32 reserveId, address user) external  returns (uint256) {
        return _getUserDepositBalance(reserveId, user);
    }

    /// @dev Pure view — no state mutation. (Bug fix: original called _updateLiquidityIndexes here)
    function getUserBorrowBalance(bytes32 reserveId, address user) external returns (uint256) {
        return _getUserBorrowBalance(reserveId, user);
    }

    function getUtilizationRate(bytes32 reserveId) external view override returns (uint256) {
        DataTypes.ReserveData storage r = _getReserve(reserveId);
        return MathLib.utilizationRate(r.totalBorrows, r.totalDeposits);
    }

    /// @dev Returns only open positions — no empty slots (bug fix vs original).
    function getUserPositions(address user) external view override returns (DataTypes.Position[] memory) {
        DataTypes.Position[] storage all = _positions[user];
        uint256 len = all.length;

        // Count open
        uint256 openCount;
        for (uint256 i; i < len; ++i) {
            if (all[i].isOpen) ++openCount;
        }

        DataTypes.Position[] memory result = new DataTypes.Position[](openCount);
        uint256 idx;
        for (uint256 i; i < len; ++i) {
            if (all[i].isOpen) {
                result[idx++] = all[i];
            }
        }
        return result;
    }
    function getPosition(address user, uint256 positionId) external view returns (DataTypes.Position memory) {
        return _getPosition(user, positionId);
    }

    function checkPositionHealth(address user, uint256 positionId) external view override returns (bool) {
        return _checkHealth(user, positionId);
    }
}
