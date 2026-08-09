// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IPriceOracle} from "../../src/interfaces/IPriceOracle.sol";

/// @title MockOracle
/// @notice Test-only IPriceOracle. Maps feed addresses to RAY-scaled prices
///         that can be updated per test. Replaces the old MockAggregator which
///         required wiring a separate Chainlink-shaped contract per asset.
contract MockOracle is IPriceOracle {
    mapping(address => uint256) private _prices; // feed → RAY-scaled USD price

    // ── Setup helpers ────────────────────────────────────────────────

    function setPrice(address feed, uint256 priceRay) external {
        _prices[feed] = priceRay;
    }

    function setPrices(address[] calldata feeds, uint256[] calldata prices) external {
        require(feeds.length == prices.length, "MockOracle: length mismatch");
        for (uint256 i; i < feeds.length; ++i) {
            _prices[feeds[i]] = prices[i];
        }
    }

    // ── IPriceOracle ────────────────────────────────────────────────

    function getPrice(address priceFeed) external view override returns (uint256) {
        uint256 p = _prices[priceFeed];
        require(p != 0, "MockOracle: price not set");
        return p;
    }
}
