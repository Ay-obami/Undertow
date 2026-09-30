# Token-flow rounding policy

## Problem

Nearest rounding treats credits and debits symmetrically. At a large liquidity index, an outgoing withdrawal can burn zero scaled deposit units, debt issuance can round below the borrowed amount, and partial repayment can forgive more debt than its token payment covers. A positive deposit/repayment can also have no representable scaled value.

## Design

Use full-precision floor/ceiling scaling at token-flow boundaries. Preserve nearest rounding for the existing interest-index and displayed real-balance calculations.

| Flow | Scaled conversion | Reason |
| --- | --- | --- |
| Deposit credit | Down; reject zero units | Credit no more than received tokens |
| Partial withdrawal | Up | Burn enough claim units for the outgoing payment |
| Full displayed-balance withdrawal | Entire user scaled balance | Allow a complete exit despite displayed-balance rounding |
| New debt | Up | Record at least the amount borrowed |
| Collateral lock | Up, or entire scaled balance for a full lock | Do not leave free claim units behind the fixed lock |
| Partial repayment | Down; reject zero units | Do not forgive more debt than paid |
| Returned collateral deposit credit | Down | Do not mint extra free claims |

Collateral requirements are calculated from reconstructed rounded issued debt, not just the requested token amount; opening health must remain acceptable. Partial collateral release follows the fraction of scaled debt actually removed, rounded down. Full repayment continues to remove the exact remaining debt and release all remaining fixed collateral into a floor-converted free deposit claim; any unrepresentable credit dust is unallocated surplus. Reject a computed zero-collateral borrow. Recheck borrow cap and utilization against the synchronized rounded debt total.

## Verification and limits

Reproduce failures against unchanged contracts, then run existing tests and large-index amount fuzzing. Check outgoing payments against burned claims, incoming payments against credited claims, debt against disbursed tokens, repayment against forgiven debt, complete exits, and fixed-lock versus free-claim conservation.

Rounding can cost a user dust below one scaled unit's token value; that cost grows with the liquidity index. No partial repayment/deposit that maps to zero units is accepted. These are intentional user-visible boundary changes and require a fresh deployment to affect existing pools. The public interfaces stay unchanged.

This is not a proof of all protocol arithmetic. Legacy rate/price/display calculations, adversarial token callbacks, reentrancy, oracle risk, bad debt and unsupported token behavior need separate review. Conservation comparisons across independently rounded users still need explicit smallest-unit tolerances.
