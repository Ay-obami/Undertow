# Oracle input validation

Oracle reads require positive raw prices and strictly positive prices after conversion to the protocol's 1e18 USD scale. Values smaller than that scale can represent are rejected instead of returning a zero collateral or debt valuation.

Completed timestamps must be nonzero, no later than the current block, and no older than the configured stale period. The exact stale boundary is accepted. Chainlink additionally requires answeredInRound to be at least roundId.

Chainlink decimal precision supports 0 through 95 inclusive. Decimal precision above 18 divides by 10^(decimals - 18); the maximum supported exponent is 77, which fits uint256. Multiplication that cannot fit uint256 remains fail closed through checked arithmetic. Feeds with unsupported precision, invalid data, or a zero normalized price cannot be used for valuation.

Feed selection remains a trusted reserve configuration responsibility: each configured Chainlink address must provide the intended USD feed with a suitable heartbeat for the chosen stale period. The adapter validates data, not the economic identity of a feed.

FTSO uses owner-registered logical feed keys. Its supported signed-decimal range is 0 through 95; negative decimals remain explicitly unsupported by MathLib. The zero timestamp check is independent of the stale window, including immediately after genesis or when a large stale period is configured. This adapter retains the fee-free Coston2 TestFtsoV2 interface and is not a mainnet paid-read implementation.
