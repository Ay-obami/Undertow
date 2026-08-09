// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {DataTypes} from "../libraries/DataTypes.sol";
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

    // ================================================================
    // Shared helpers
    // ================================================================

    modifier onlyOwner() {
        require(msg.sender == _owner, "PoolStorage: not owner");
        _;
    }

    function _getReserve(bytes32 id) internal view returns (DataTypes.ReserveData storage r) {
        r = _reserves[id];
        require(r.tokenAddress != address(0), "PoolStorage: unknown reserve");
    }

    function _getPosition(
        address user,
        uint256 positionId
    ) internal view returns (DataTypes.Position storage p) {
        require(positionId < _positions[user].length, "PoolStorage: bad position id");
        p = _positions[user][positionId];
        require(p.isOpen, "PoolStorage: position closed");
    }
}
