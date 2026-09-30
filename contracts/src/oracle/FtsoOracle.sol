// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IPriceOracle} from "../interfaces/IPriceOracle.sol";
import {MathLib} from "../libraries/MathLib.sol";
import {ContractRegistry} from "@flarenetwork/flare-periphery-contracts/coston2/ContractRegistry.sol";
import {TestFtsoV2Interface} from "@flarenetwork/flare-periphery-contracts/coston2/TestFtsoV2Interface.sol";

/// @title FtsoOracle
/// @notice IPriceOracle implementation backed by Flare's FTSOv2 block-latency feeds.
///
///         Design note — keeping IPriceOracle's `getPrice(address)` signature:
///         FTSOv2 feeds are identified by a `bytes21` feed ID (category + symbol,
///         e.g. "01" + "FLR/USD"), not an address. Rather than widen IPriceOracle
///         (and every ReserveConfig/Position struct that stores `priceFeed` as an
///         address) across the whole codebase, this oracle keeps a
///         `feedKey => bytes21 feedId` mapping internally. Reserves are configured
///         exactly as before — `cfg.priceFeed` is still an address — except for
///         FTSO-backed reserves that address is a logical "feed key" (by convention,
///         the reserve's own token address) that the owner maps to a real FTSOv2
///         feed ID via `setFeedId` before the reserve goes live. This is a drop-in
///         replacement for ChainlinkOracle; Pool/PoolStorage/DataTypes are untouched.
///
///         Testnet vs mainnet:
///         `TestFtsoV2Interface` (used here) exposes fee-free `view` reads and is
///         intended for testing per Flare's own docs. It matches this codebase's
///         `getPrice` being `view`. For a mainnet deployment, swap to
///         `FtsoV2Interface` (payable, non-view, requires paying a read fee via
///         `IFeeCalculator`) — that is out of scope for the Coston2/Songbird
///         hackathon target and is left as a follow-up.
///
///         Staleness guard: FTSOv2 block-latency feeds update roughly once per
///         block/voting round; this contract reverts if the feed timestamp is
///         older than `stalePeriod`, mirroring ChainlinkOracle's guard.
contract FtsoOracle is IPriceOracle {
    /// @notice Max age (seconds) a feed timestamp may have before reads revert.
    uint256 public immutable stalePeriod;

    /// @notice Protocol owner — the only account allowed to register feed IDs.
    address public immutable owner;

    /// @dev feedKey (the `priceFeed` address stored on the reserve) => FTSOv2 feed id.
    mapping(address => bytes21) private _feedIds;

    event FeedIdSet(address indexed feedKey, bytes21 indexed feedId);

    modifier onlyOwner() {
        require(msg.sender == owner, "FtsoOracle: not owner");
        _;
    }

    constructor(uint256 _stalePeriod, address _owner) {
        require(_stalePeriod > 0, "FtsoOracle: zero stale period");
        require(_owner != address(0), "FtsoOracle: zero owner");
        stalePeriod = _stalePeriod;
        owner = _owner;
    }

    /// @notice Registers (or updates) the FTSOv2 feed id backing a given feed key.
    /// @param feedKey  The address used as `priceFeed` on the reserve config
    ///                 (by convention, the reserve's token address).
    /// @param feedId   The FTSOv2 feed id, e.g. category 1 + "XRP/USD".
    function setFeedId(address feedKey, bytes21 feedId) external onlyOwner {
        require(feedKey != address(0), "FtsoOracle: zero feed key");
        require(feedId != bytes21(0), "FtsoOracle: zero feed id");
        _feedIds[feedKey] = feedId;
        emit FeedIdSet(feedKey, feedId);
    }

    /// @notice Returns the FTSOv2 feed id registered for a feed key (zero if unset).
    function feedIdOf(address feedKey) external view returns (bytes21) {
        return _feedIds[feedKey];
    }

    /// @inheritdoc IPriceOracle
    function getPrice(address priceFeed) external view override returns (uint256) {
        bytes21 feedId = _feedIds[priceFeed];
        require(feedId != bytes21(0), "FtsoOracle: feed not registered");

        /* THIS IS A TEST INTERFACE — free `view` reads, intended for testnet use.
           For production/mainnet, swap to FtsoV2Interface (payable) — see contract
           docs above. */
        TestFtsoV2Interface ftsoV2 = ContractRegistry.getTestFtsoV2();

        (uint256 value, int8 decimals, uint64 timestamp) = ftsoV2.getFeedById(feedId);

        require(value > 0, "FtsoOracle: non-positive price");
        require(timestamp != 0, "FtsoOracle: round not complete");
        require(timestamp <= block.timestamp, "FtsoOracle: future timestamp");
        require(block.timestamp - timestamp <= stalePeriod, "FtsoOracle: price stale");

        require(decimals <= 95, "FtsoOracle: unsupported decimals");
        uint256 priceRay = MathLib.ftsoToRay(value, decimals);
        require(priceRay > 0, "FtsoOracle: price below precision");
        return priceRay;
    }
}
