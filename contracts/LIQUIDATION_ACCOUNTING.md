# Liquidation collateral accounting

Borrowing locks collateral by removing it from the user's free scaled deposit balance. It keeps that collateral in the reserve's total deposits because the tokens remain in the pool. Repayment restores the collateral as a deposit without moving tokens out of the pool.

Liquidation instead sends the seized amount to the liquidator and any leftover directly to the borrower. Their sum is the entire locked collateral amount. The collateral reserve now records a withdrawal of that full amount before either outgoing transfer. Subtracting only the seized amount would leave borrower leftovers recorded as phantom deposits. A failed transfer or reserve-accounting check rolls back the transaction.

Tests compare reserve totals with pool token balances and remaining depositor claims in a collateral reserve with no outstanding borrows. They exercise a range of unhealthy prices, with and without borrower leftovers, withdrawals to zero, and rejected healthy-position liquidation.

If accrued collateral claims exceed the principal-based reserve total, the withdrawal check can revert liquidation. The aggregate accounting model must be repaired to support that case; this patch fails closed rather than subtracting an amount the reserve does not record.

This does not resolve accrued supply/borrow aggregate accounting, bad-debt policy, outgoing transfer-tax behavior, rounding, or callback/reentrancy risks. Existing contracts require a new deployment to receive this source change.
