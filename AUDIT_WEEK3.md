# Liquidation re-audit — Week 3

Re-verification of the four bugs the PRD lists as previously self-audited,
against this ported codebase. Tests: `contracts/test/unit/BugAudit.t.sol`.

| # | Bug | Status found | Fix |
|---|-----|---------------|-----|
| 1 | Missing transfer in `repay` | **Already fixed** in this codebase | `BorrowModule._repay` calls `safeTransferFrom` before touching state |
| 2 | Unapplied liquidation bonus | **Already fixed** in this codebase | `LiquidationModule._liquidate` scales seized collateral by `(1 + liquidationBonus)` |
| 3 | Oracle decimal mismatch | **Already fixed** in this codebase | `ChainlinkOracle`/`FtsoOracle` both read the feed's native decimals and normalise to RAY (`MathLib.chainlinkToRay` / `ftsoToRay`) |
| 4 | Stale borrow-index health checks | **Found still present — fixed in this PR** | See below |

## Bug 4 — the one that needed fixing

`LiquidationModule._checkHealth` (backing the public `checkPositionHealth`)
read `borrowReserve.borrowLiquidityIndex` directly from storage. That index
is only advanced by `ReserveLib.updateIndexes`, which is only called from
state-*changing* functions (`deposit`, `borrow`, `repay`, `liquidate`) —
never from a `view` function, because it writes to storage.

Practical effect: a position's on-chain "is this healthy?" answer could stay
frozen at whatever the borrow index was the last time *anyone* touched that
reserve, understating accrued interest for every second since. A position
could silently cross into unhealthy territory and still report `true` from
`checkPositionHealth` — and by extension, anything reading that view (a
frontend, a keeper bot deciding whether to call `liquidate`) would
under-detect risk until some unrelated deposit/borrow/repay happened to
refresh the reserve.

**Fix:** `ReserveLib.previewBorrowIndex(reserve)` — a non-mutating `view`
function that mirrors `updateIndexes`'s borrow-side math (utilization → rate
→ `MathLib.compoundIndex`) without writing to storage. `_checkHealth` now
calls this instead of reading the stored index directly.

```solidity
// before
uint256 debtReal = MathLib.toReal(pos.scaledDebt, borrowReserve.borrowLiquidityIndex);

// after
uint256 debtReal = MathLib.toReal(pos.scaledDebt, borrowReserve.previewBorrowIndex());
```

`_liquidate` itself was never affected — it's state-changing and already
calls `updateIndexes()` before reading the index, so its debt figure was
always current. Only the `view`-only health check path had the bug.

### Test coverage

- `test_Bug4_HealthCheck_ReflectsAccruedInterest_WithNoIntermediateTouch` —
  opens a position at ~90% reserve utilization, warps 365 days with *no*
  other interaction touching that reserve, and asserts `checkPositionHealth`
  correctly flips to unhealthy. This test fails against the pre-fix code
  (health check stays `true` forever) and passes against the fix.
- `test_Bug4_HealthCheck_MatchesPostTouchValue` — confirms the view-only
  preview isn't just *different* from the stale read, it's *correct*: it
  matches the real index once something else finally touches the reserve
  and `updateIndexes()` actually runs.

### Why the other three didn't need new production code

Bugs 1–3 were already fixed by the time this repo was ported (each has a
`// Bug fix vs original` comment at the point of the fix). What Week 3's
"re-verify" deliverable meant for those was writing tests that would fail if
the bug were re-introduced — `test_Bug1_*`, `test_Bug2_*`, `test_Bug3_*` in
`BugAudit.t.sol` do exactly that, rather than duplicating coverage that
already exists in `BorrowModule.t.sol`/`LiquidationModule.t.sol`/`MathLib.t.sol`.
