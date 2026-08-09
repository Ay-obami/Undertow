// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title IPriceOracle
/// @notice Thin oracle abstraction used by pool modules.
///         Implementations handle decimal normalisation internally so
///         callers always receive a RAY (1e18) scaled USD price.
interface IPriceOracle {
    /// @notice Returns the RAY-scaled USD price for the given feed address.
    /// @dev    Reverts if price is stale, invalid, or the feed is unsupported.
    function getPrice(address priceFeed) external view returns (uint256 priceRay);
}
