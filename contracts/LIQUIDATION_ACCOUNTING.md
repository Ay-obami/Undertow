# Liquidation collateral accounting

Borrowing locks collateral by removing it from the user's free scaled deposit balance. It keeps that collateral in the reserve's total deposits because the tokens remain in the pool. Repayment restores the collateral as a deposit without moving tokens out of the pool.

Liquidation instead sends the seized amount to the liquidator and any leftover directly to the borrower. Their sum is the entire locked collateral amount. The collateral reserve removes that full fixed amount from its aggregate locked claims before either outgoing transfer; reserve totals are derived from scaled free claims plus the remaining fixed locked claims. Subtracting only the seized amount would leave borrower leftovers recorded as phantom deposits. A failed transfer or reserve-accounting check rolls back the transaction.

Tests compare reserve totals with pool token balances and remaining depositor claims in a collateral reserve with no outstanding borrows. They exercise a range of unhealthy prices, with and without borrower leftovers, withdrawals to zero, and rejected healthy-position liquidation.

The earlier principal-based withdrawal check could revert if accrued collateral claims exceeded the original deposit total. Scaled aggregate accounting now tracks free accrued claims and fixed locked claims separately; see SCALED_ACCOUNTING.md and the accrued-collateral liquidation regression.

Further review is required for bad-debt policy, outgoing transfer-tax behavior, rounding, or callback/reentrancy risks. Existing contracts require a new deployment to receive this source change.
