// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title MockFtsoV2
/// @notice Test-only stand-in for Flare's TestFtsoV2Interface. Lets tests set
///         a (value, decimals, timestamp) triple per feed id and have
///         FtsoOracle read it exactly as it would read the real FTSOv2 contract.
contract MockFtsoV2 {
    struct Feed {
        uint256 value;
        int8 decimals;
        uint64 timestamp;
    }

    mapping(bytes21 => Feed) private _feeds;

    function setFeed(bytes21 feedId, uint256 value, int8 decimals, uint64 timestamp) external {
        _feeds[feedId] = Feed(value, decimals, timestamp);
    }

    function getFeedById(bytes21 feedId)
        external
        view
        returns (uint256 _value, int8 _decimals, uint64 _timestamp)
    {
        Feed memory f = _feeds[feedId];
        return (f.value, f.decimals, f.timestamp);
    }
}
