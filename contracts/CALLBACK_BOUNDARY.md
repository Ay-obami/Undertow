# Pool callback boundary

## Policy

Deposit, withdrawal, borrowing, repayment and liquidation are complete, mutually exclusive state transitions. An external token call during one transition must not enter any of those five actions, including actions on a different reserve. Sequential transactions remain supported.

The pool facade inherits the pinned OpenZeppelin storage-based `ReentrancyGuard` and applies its shared `nonReentrant` modifier to all five action entry points. Internal module functions remain unchanged. This guard does not require EIP-1153 transient-storage support. Nested action calls reject with `ReentrancyGuardReentrantCall()`.

## Why exact receipts are insufficient

An incoming payment compares the balance of the payment token before and after transfer. A callback that changes another reserve can leave that measured receipt exact and still enter the pool during an unfinished transition. Regression fixtures use exact-transfer ERC-20 balances, genuine callback-caller deposits/approvals/debt, and an unhealthy liquidation target; no forged balance response is needed.

This is hardening of the action boundary. The regression demonstrates allowed nested actions, not a funds-loss exploit.

## Verification

`test/unit/CallbackReentrancy.t.sol` checks every outer/nested action pair (5 × 5) using isolated snapshots. It exercises incoming and outgoing token callbacks, checks the exact rejection error, confirms nested claims/debt/tokens are unchanged, and executes another action afterward. A propagated callback error must roll back the outer deposit, token movement and totals. A standalone control demonstrates that all nested actions are otherwise valid.

## Limits and deployment

Views remain callable during a transition and may expose intermediate state; integrations must not treat callback-time reads as a settlement guarantee. Owner-only reserve administration remains outside this mutex. Listing authority, arbitrary token behavior, balance lies, outgoing fees, rebases, oracle semantics and economic solvency still need separate review. Callback tokens remain unsupported generally; rejecting nested actions does not certify them.

Pool action signatures and module arithmetic are unchanged; the inherited guard adds an error and a namespaced storage slot initialized by the constructor. There is no proxy migration in this change. Existing deployments are unaffected, and deployment bytecode changes. Deploy a new pool to use this policy.
