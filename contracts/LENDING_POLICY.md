# Lending policy and deployment boundary

## Asset units and reserve configuration

Amounts, caps and locked collateral use each token's native units. Prices use 18-decimal USD units (the project's historical `RAY` constant is 1e18). Token decimals are cached when a reserve is listed; supported precision is 0–18. A token may have only one reserve. Tokens must expose stable metadata and exact incoming transfers. Rebasing, dishonest balance reporting and outgoing-transfer fees are unsupported.

Reserve listing validates nonzero deployed token/strategy contracts, positive LTV below a liquidation threshold at most 100%, reserve factor at most 100%, an optimal utilization strictly between zero and 100%, individual rate components and liquidation bonus at most 100%, and positive caps. These bounds prevent malformed configuration; they do not establish sensible market risk. Administrators remain trusted to select assets, feeds, strategies and parameters.

## Collateral and liquidity

Locked collateral is a fixed quantity of underlying tokens, earns no supply interest while locked, and must remain backed by pool cash. New locks reject when existing cash cannot back all locks. Borrowing and withdrawal consume only cash above the locked amount. This deliberately reduces available borrowing liquidity: the protocol transfers underlying collateral immediately during liquidation rather than issuing a claim that may be redeemed later.

An inactive reserve rejects new deposits, borrowing and withdrawals. Repayment and liquidation remain available. The owner must reactivate a reserve before suppliers can withdraw released collateral. This pause policy is tested and is not an unconditional withdrawal escape hatch.

## Liquidation economics

Liquidation requires an unhealthy position and **payment of the full accrued debt**. The liquidator receives debt-equivalent collateral plus the configured bonus, capped at all locked collateral. Any leftover underlying returns directly to the borrower. Failed payment rolls the entire transaction back and preserves the debt and collateral.

If collateral value falls below debt, a willing liquidator still pays the full debt for less valuable collateral. This is economically unattractive and may never occur. The protocol does not erase unpaid residual debt, guarantee liquidation liveness, provide an insurance fund, implement partial liquidation/close factors, or distribute losses through a bad-debt waterfall. Suppliers can therefore face illiquidity and economic loss after oracle-price shocks or borrower default. Do not market the full-debt rule as insolvency resolution.

## Arithmetic and testing scope

Token-boundary scaling is directional; legacy display, rate and valuation operations retain nearest rounding with full-precision multiplication. Smallest-unit costs and dust remain documented in `DIRECTIONAL_ROUNDING.md`. Stateful tests cover three actors, two reserves, bounded time and action sequences with independent token-flow tracking. Index-phase tests add strict claim/debt-versus-payment comparisons and complete exits. These finite scenarios do not establish all rate, market, oracle or insolvency properties.

## Fresh deployment required

This source adds storage, a shared action guard, token metadata and additive view functions. Use a fresh deployment; no populated-pool migration is supplied. Existing deployed addresses do not gain these changes. Configure the new pool address and matching chain in the frontend only after deployment. Local and pinned-fork rehearsals do not constitute a public deployment.

`Lending_Borrowing_Protocol` is the canonical shared-core repository. Undertow is a separately maintained Flare research fork. Its proof and paymaster experiments are outside the supported direct-wallet lending scope; see Undertow's `SCOPE.md`.
