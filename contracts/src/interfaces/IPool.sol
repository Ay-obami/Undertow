// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {DataTypes} from "../libraries/DataTypes.sol";

/// @title IPool
/// @notice External interface for the lending pool facade.
///         All user-facing and integrator-facing functions live here.
interface IPool {
    // ================================================================
    // Events
    // ================================================================

    event ReserveInitialized(
        bytes32 indexed reserveId,
        string reserveName,
        address indexed tokenAddress,
        address indexed priceFeed,
        uint256 ltv,
        uint256 liquidationThreshold
    );
    event ReserveStatusUpdated(bytes32 indexed reserveId, bool isActive);
    event ReserveBorrowStatusUpdated(bytes32 indexed reserveId, bool isBorrowable);
    event Deposit(address indexed user, bytes32 indexed reserveId, uint256 amount, uint256 scaledAmount);
    event Withdraw(address indexed user, bytes32 indexed reserveId, uint256 amount, uint256 scaledAmount);
    event Borrow(
        address indexed user,
        bytes32 indexed borrowReserveId,
        bytes32 indexed collateralReserveId,
        uint256 amount,
        uint256 collateralLocked,
        uint256 positionId
    );
    event Repay(
        address indexed user,
        bytes32 indexed borrowReserveId,
        bytes32 indexed collateralReserveId,
        uint256 repayAmount,
        uint256 collateralReleased,
        uint256 positionId
    );
    event Liquidated(
        address indexed user,
        address indexed liquidator,
        bytes32 indexed collateralReserveId,
        bytes32 borrowReserveId,
        uint256 debtRepaid,
        uint256 collateralSeized,
        uint256 positionId
    );
    event LiquidityIndexUpdated(bytes32 indexed reserveId, uint256 supplyIndex, uint256 borrowIndex);

    // ================================================================
    // Core user actions
    // ================================================================

    function deposit(bytes32 reserveId, uint256 amount) external;

    function withdraw(bytes32 reserveId, uint256 amount) external;

    function borrow(bytes32 collateralId, bytes32 borrowId, uint256 amount, uint256 bufferPercent) external;

    function repay(bytes32 collateralId, bytes32 borrowId, uint256 positionId, uint256 repayAmount) external;

    function liquidate(address user, uint256 positionId) external;

    // ================================================================
    // Admin
    // ================================================================

    function addReserve(DataTypes.ReserveConfig calldata config) external;

    function setReserveActive(bytes32 reserveId, bool active) external;

    function setReserveBorrowable(bytes32 reserveId, bool borrowable) external;

    // ================================================================
    // Views
    // ================================================================

    function getReserve(bytes32 reserveId) external view returns (DataTypes.ReserveData memory);

    function getAllReserves() external view returns (DataTypes.ReserveData[] memory);

    function getReserveId(string calldata name) external pure returns (bytes32);

    function getUserDepositBalance(bytes32 reserveId, address user) external  returns (uint256);

    function getUserBorrowBalance(bytes32 reserveId, address user) external  returns (uint256);

    function getUtilizationRate(bytes32 reserveId) external view returns (uint256);

    function getUserPositions(address user) external view returns (DataTypes.Position[] memory);

    function checkPositionHealth(address user, uint256 positionId) external view returns (bool);
}
