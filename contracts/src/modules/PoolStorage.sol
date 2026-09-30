// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {DataTypes} from "../libraries/DataTypes.sol";
import {MathLib} from "../libraries/MathLib.sol";
import {ReserveLib} from "../libraries/ReserveLib.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPool} from "../interfaces/IPool.sol";

/// @title PoolStorage
/// @notice Declares ALL storage slots used by Pool modules.
///         Every module inherits from this — no module declares its own storage,
///         which prevents storage-collision bugs in the inheritance chain.
///
///         Also exposes the shared internal helpers (_getReserve, _getPosition)
///         so modules don't duplicate the same require() statements.
abstract contract PoolStorage is IPool {
    // ================================================================
    // Storage
    // ================================================================

    /// @dev  reserveId (bytes32) → ReserveData
    mapping(bytes32 => DataTypes.ReserveData) internal _reserves;

    /// @dev  reserveId → user → scaledDeposit balance
    mapping(bytes32 => mapping(address => uint256)) internal _scaledDeposits;

    /// @dev  user → array of positions (never shrinks; closed positions flagged isOpen=false)
    mapping(address => DataTypes.Position[]) internal _positions;

    /// @dev  Ordered list of active reserve IDs for iteration
    bytes32[] internal _reserveIds;

    /// @dev  IPriceOracle address — set by Pool constructor / initialiser
    address internal _oracle;

    /// @dev  Protocol owner — set by Pool constructor
    address internal _owner;

    /// @dev Authoritative aggregate claim counters; fresh deployments only.
    mapping(bytes32 => uint256) internal _totalScaledDeposits;
    mapping(bytes32 => uint256) internal _totalScaledDebt;
    mapping(bytes32 => uint256) internal _totalLockedCollateral;

    mapping(bytes32 => uint8) internal _tokenDecimals;
    mapping(address => bool) internal _listedTokens;

    /// @dev Fixed collateral is held in custody and cannot fund loans or free-claim exits.
    function _availableCash(bytes32 id) internal view returns (uint256) {
        uint256 cash = IERC20(_reserves[id].tokenAddress).balanceOf(address(this));
        uint256 reserved = _totalLockedCollateral[id];
        return cash > reserved ? cash - reserved : 0;
    }

    /// @dev USD values use 18 decimals; token balances retain their native precision.
    function _assetValue(bytes32 id, uint256 amount, uint256 price) internal view returns (uint256) {
        return MathLib.mulDivNearest(amount, price, 10 ** uint256(_tokenDecimals[id]));
    }

    function _assetAmount(bytes32 id, uint256 value, uint256 price) internal view returns (uint256) {
        return MathLib.mulDivNearest(value, 10 ** uint256(_tokenDecimals[id]), price);
    }

    // ================================================================
    // Shared helpers
    // ================================================================

    modifier onlyOwner() {
        require(msg.sender == _owner, "PoolStorage: not owner");
        _;
    }

    function _syncReserveTotals(bytes32 id) internal {
        DataTypes.ReserveData storage reserve = _reserves[id];
        reserve.totalBorrows = MathLib.toReal(_totalScaledDebt[id], reserve.borrowLiquidityIndex);
        reserve.totalDeposits =
            MathLib.toReal(_totalScaledDeposits[id], reserve.supplyLiquidityIndex) + _totalLockedCollateral[id];
    }

    function _accrueReserve(bytes32 id) internal {
        ReserveLib.updateIndexes(_reserves[id]);
        _syncReserveTotals(id);
    }

    function _getReserve(bytes32 id) internal view returns (DataTypes.ReserveData storage r) {
        r = _reserves[id];
        require(r.tokenAddress != address(0), "PoolStorage: unknown reserve");
    }

    function _getPosition(address user, uint256 positionId) internal view returns (DataTypes.Position storage p) {
        require(positionId < _positions[user].length, "PoolStorage: bad position id");
        p = _positions[user][positionId];
        require(p.isOpen, "PoolStorage: position closed");
    }
}
