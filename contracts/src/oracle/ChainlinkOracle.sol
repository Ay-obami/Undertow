// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IPriceOracle} from "../interfaces/IPriceOracle.sol";
import {MathLib} from "../libraries/MathLib.sol";

interface AggregatorV3Interface {
    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );

    function decimals() external view returns (uint8);
}

/// @title ChainlinkOracle
/// @notice IPriceOracle implementation backed by Chainlink AggregatorV3.
///
///         Bug fix vs original:
///           Original Pool.getPrice() divided by RAY (1e18) without normalising
///           the Chainlink answer (which uses 8 decimals). This contract reads
///           `feed.decimals()` and scales the answer to RAY before returning,
///           so callers always receive a consistent 1e18-scaled USD price.
///
///         Staleness guard: reverts if the answer is older than `stalePeriod`.
contract ChainlinkOracle is IPriceOracle {
    uint256 public immutable stalePeriod;

    constructor(uint256 _stalePeriod) {
        require(_stalePeriod > 0, "ChainlinkOracle: zero stale period");
        stalePeriod = _stalePeriod;
    }

    /// @inheritdoc IPriceOracle
    function getPrice(address priceFeed) external view override returns (uint256) {
        AggregatorV3Interface feed = AggregatorV3Interface(priceFeed);

        (
            uint80 roundId,
            int256 answer,
            ,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = feed.latestRoundData();

        require(answer > 0,                             "ChainlinkOracle: non-positive price");
        require(updatedAt != 0,                         "ChainlinkOracle: round not complete");
        require(answeredInRound >= roundId,             "ChainlinkOracle: stale round");
        require(block.timestamp - updatedAt <= stalePeriod, "ChainlinkOracle: price stale");

        uint8 dec = feed.decimals();
        // Normalise to RAY (1e18) — fixes the decimal mismatch bug in the original
        return MathLib.chainlinkToRay(answer, dec);
    }
}
