// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ChainlinkOracle} from "../../src/oracle/ChainlinkOracle.sol";

contract OracleSafetyFeed {
    uint8 public decimals = 8;
    int256 public answer = 1e8;
    uint80 public roundId = 10;
    uint80 public answeredInRound = 10;
    uint256 public updatedAt;

    constructor() {
        updatedAt = block.timestamp;
    }

    function configure(int256 value, uint8 precision, uint256 time, uint80 completedRound) external {
        answer = value;
        decimals = precision;
        updatedAt = time;
        answeredInRound = completedRound;
    }

    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        return (roundId, answer, updatedAt, updatedAt, answeredInRound);
    }
}

contract ChainlinkOracleSafetyTest is Test {
    ChainlinkOracle internal oracle;
    OracleSafetyFeed internal feed;

    function setUp() public {
        vm.warp(10_000);
        oracle = new ChainlinkOracle(300);
        feed = new OracleSafetyFeed();
    }

    function test_RejectsPriceThatNormalisesToZero() public {
        feed.configure(1, 19, block.timestamp, 10);
        vm.expectRevert("ChainlinkOracle: price below precision");
        oracle.getPrice(address(feed));
    }

    function test_RejectsUnsupportedExponentExplicitly() public {
        feed.configure(1, 96, block.timestamp, 10);
        vm.expectRevert("ChainlinkOracle: unsupported decimals");
        oracle.getPrice(address(feed));
    }

    function test_RejectsFutureTimestampExplicitly() public {
        feed.configure(1e8, 8, block.timestamp + 1, 10);
        vm.expectRevert("ChainlinkOracle: future timestamp");
        oracle.getPrice(address(feed));
    }

    function test_AcceptsExactStaleBoundary() public {
        feed.configure(1e8, 8, block.timestamp - 300, 10);
        assertEq(oracle.getPrice(address(feed)), 1e18);
    }

    function test_RejectsStaleRound() public {
        feed.configure(1e8, 8, block.timestamp, 9);
        vm.expectRevert("ChainlinkOracle: stale round");
        oracle.getPrice(address(feed));
    }

    function test_RejectsZeroTimestamp() public {
        feed.configure(1e8, 8, 0, 10);
        vm.expectRevert("ChainlinkOracle: round not complete");
        oracle.getPrice(address(feed));
    }
}
