# Scaled aggregate accounting

## Problem and design

Reserve totals previously tracked principal token flows while user debt and free deposit claims accrued through liquidity indexes. Repayment therefore subtracted interest from another borrower's principal, and an accrued supplier withdrawal could exceed the recorded reserve total. Liquidation of collateral earned as supply interest could fail for the same reason.

Maintain three shared per-reserve counters in PoolStorage:

- The sum of user scaled free deposits.
- The sum of scaled debt on open positions.
- The sum of fixed real collateral locked by open positions.

After index accrual and each claim mutation, derive `totalBorrows` from aggregate scaled debt and the borrow index; derive `totalDeposits` from aggregate scaled free deposits and the supply index, plus fixed locked collateral. These totals are stored snapshots at the last update, as the existing reserve getters already expose. User balance reads continue to preview indexes without changing storage.

Locked collateral retains the existing policy: it is fixed in token units and does not earn supply interest while locked. Locking removes scaled free deposits and adds fixed collateral; repayment reverses the released portion at the current supply index; liquidation removes the full remaining fixed collateral because all of it leaves the pool. Interest on free claims is paid according to the existing utilization/rate model. Unallocated token surplus is not an additional depositor claim.

Full repayment/liquidation removes the position's exact remaining scaled debt. Partial repayment removes the same scaled amount from the position and aggregate. Borrow-cap checks run after accrual so interest cannot be omitted from the cap calculation.

## Implementation and validation

1. Reproduce debt repayment, accrued withdrawal, accrued collateral liquidation and locked/free claim mismatches against unchanged contracts.
2. Add counters and accrual/synchronization helpers; wire supply, borrow, repayment and liquidation updates to identical scaled deltas.
3. Compare aggregate totals with individual claims through elapsed-time partial/full repayments and collateral transitions; compare cash plus debt with supplier claims within explicit per-claim rounding tolerance.
4. Run existing full suites, fuzzing and independent review before merging.

The public ReserveData tuple, function selectors and existing interest-rate formula remain unchanged. Internal storage changes require fresh deployments; this is not an in-place storage migration, and counters cannot be initialized from a populated old deployment without reconstructing every claim.

## Limits

Aggregating then rounding can differ from summing individually rounded claims by a few smallest token units. Tests must state tolerances rather than claim exact cross-user equality. Integer rounding, extreme index/dust behavior, token callbacks/reentrancy, outgoing token taxes, oracle safety, economic bad debt, and transaction-by-transaction solvency under adversarial execution require further review. Reserve getters remain snapshots; this change does not make all reserve views live accrued balances. No public deployment is part of this patch.
