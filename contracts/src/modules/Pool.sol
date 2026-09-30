// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
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
///         A shared ReentrancyGuard protects all five user action entry points.
contract Pool is SupplyModule, BorrowModule, LiquidationModule, ReentrancyGuard {
    using ReserveLib for DataTypes.ReserveData;
    using MathLib for uint256;

    // ================================================================
    // Constructor
    // ================================================================

    constructor(address oracle) {
        require(oracle != address(0), "Pool: zero oracle");
        require(oracle.code.length > 0, "Pool: oracle has no code");
        _oracle = oracle;
        _owner = msg.sender;
    }

    // ================================================================
    // IPool — core user actions
    // ================================================================

    /// test
    function deposit(bytes32 reserveId, uint256 amount) external override nonReentrant {
        _deposit(reserveId, amount);
    }

    function withdraw(bytes32 reserveId, uint256 amount) external override nonReentrant {
        _withdraw(reserveId, amount);
    }

    function borrow(bytes32 collateralId, bytes32 borrowId, uint256 amount, uint256 bufferPercent)
        external
        override
        nonReentrant
    {
        _borrow(collateralId, borrowId, amount, bufferPercent);
    }

    function repay(bytes32 collateralId, bytes32 borrowId, uint256 positionId, uint256 repayAmount)
        external
        override
        nonReentrant
    {
        _repay(collateralId, borrowId, positionId, repayAmount);
    }

    function liquidate(address user, uint256 positionId) external override nonReentrant {
        _liquidate(user, positionId);
    }

    // ================================================================
    // IPool — admin
    // ================================================================

    function addReserve(DataTypes.ReserveConfig calldata cfg) external override onlyOwner {
        bytes32 id = getReserveId(cfg.name);
        require(_reserves[id].tokenAddress == address(0), "Pool: reserve exists");
        require(cfg.tokenAddress != address(0), "Pool: zero token");
        require(cfg.priceFeed != address(0), "Pool: zero feed");
        require(cfg.interestStrategy != address(0), "Pool: zero strategy");
        require(cfg.ltv < cfg.liquidationThreshold, "Pool: ltv >= threshold");
        require(cfg.ltv > 0 && cfg.ltv <= DataTypes.RAY, "Pool: invalid ltv");
        require(cfg.liquidationThreshold <= DataTypes.RAY, "Pool: invalid liquidation threshold");
        require(cfg.reserveFactor <= DataTypes.RAY, "Pool: invalid reserve factor");
        require(
            cfg.optimalUtilization > 0 && cfg.optimalUtilization < DataTypes.RAY, "Pool: invalid optimal utilization"
        );
        require(cfg.liquidationBonus <= DataTypes.RAY, "Pool: invalid liquidation bonus");
        require(
            cfg.slope1 <= DataTypes.RAY && cfg.slope2 <= DataTypes.RAY && cfg.baseInterestRate <= DataTypes.RAY,
            "Pool: invalid rate"
        );
        require(!_listedTokens[cfg.tokenAddress], "Pool: token already listed");
        require(cfg.tokenAddress.code.length > 0, "Pool: token has no code");
        require(cfg.interestStrategy.code.length > 0, "Pool: strategy has no code");
        require(cfg.supplyCap > 0, "Pool: invalid supply cap");
        require(cfg.borrowCap > 0, "Pool: invalid borrow cap");
        uint8 precision = IERC20Metadata(cfg.tokenAddress).decimals();
        require(precision <= 18, "Pool: unsupported token decimals");
        _tokenDecimals[id] = precision;
        _listedTokens[cfg.tokenAddress] = true;

        DataTypes.ReserveData storage r = _reserves[id];
        r.id = id;
        r.name = cfg.name;
        r.tokenAddress = cfg.tokenAddress;
        r.priceFeed = cfg.priceFeed;
        r.interestStrategy = cfg.interestStrategy;
        r.liquidationThreshold = cfg.liquidationThreshold;
        r.ltv = cfg.ltv;
        r.slope1 = cfg.slope1;
        r.slope2 = cfg.slope2;
        r.baseInterestRate = cfg.baseInterestRate;
        r.optimalUtilization = cfg.optimalUtilization;
        r.liquidationBonus = cfg.liquidationBonus;
        r.reserveFactor = cfg.reserveFactor;
        r.borrowCap = cfg.borrowCap;
        r.supplyCap = cfg.supplyCap;
        r.isActive = cfg.isActive;
        r.isBorrowable = cfg.isBorrowable;
        // Index starts at RAY (1.0)
        r.supplyLiquidityIndex = DataTypes.RAY;
        r.borrowLiquidityIndex = DataTypes.RAY;
        r.lastUpdateTimestamp = block.timestamp;

        _reserveIds.push(id);

        emit ReserveInitialized(id, cfg.name, cfg.tokenAddress, cfg.priceFeed, cfg.ltv, cfg.liquidationThreshold);
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

    function getUserDepositBalance(bytes32 reserveId, address user) external view returns (uint256) {
        return _getUserDepositBalance(reserveId, user);
    }

    /// @notice Returns accrued borrow balance without updating reserve storage.
    function getUserBorrowBalance(bytes32 reserveId, address user) external view returns (uint256) {
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

    /// @notice Stable storage indices corresponding to getUserPositions, in the same order.
    function getUserPositionIds(address user) external view override returns (uint256[] memory ids) {
        DataTypes.Position[] storage positions = _positions[user];
        uint256 count;
        for (uint256 i; i < positions.length; ++i) {
            if (positions[i].isOpen) ++count;
        }
        ids = new uint256[](count);
        uint256 next;
        for (uint256 i; i < positions.length; ++i) {
            if (positions[i].isOpen) ids[next++] = i;
        }
    }

    function getReserveTokenDecimals(bytes32 reserveId) external view override returns (uint8) {
        _getReserve(reserveId);
        return _tokenDecimals[reserveId];
    }

    /// @notice Current accrued native-unit debt for an open position without changing storage.
    function getPositionDebt(address user, uint256 positionId) external view override returns (uint256) {
        DataTypes.Position storage pos = _getPosition(user, positionId);
        return MathLib.toReal(pos.scaledDebt, _reserves[pos.borrowReserveId].previewBorrowIndex());
    }

    function getPosition(address user, uint256 positionId) external view returns (DataTypes.Position memory) {
        return _getPosition(user, positionId);
    }

    function checkPositionHealth(address user, uint256 positionId) external view override returns (bool) {
        return _checkHealth(user, positionId);
    }
}
