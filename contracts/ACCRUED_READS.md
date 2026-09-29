# Accrued balance reads

`getUserDepositBalance` and `getUserBorrowBalance` are Solidity `view` functions. They preview the liquidity index at the current block timestamp with the same utilization, interest strategy, and rounding used by the next reserve update. Reads leave reserve indexes and timestamps unchanged and work under `STATICCALL`. Position health uses a current borrow-index preview.

State-changing operations continue to persist index updates. This source change requires a new deployment to affect an existing pool. Function selectors and return types are unchanged; regenerate consumer ABIs to reflect view mutability.

The previews follow the existing interest model. They do not repair aggregate principal totals, repayment interest allocation, liquidation reserve accounting, or introduce a new compounding model. Those require separate accounting review.

Regression tests cover elapsed-time static calls, reserve immutability, unchanged same-timestamp balances, preview agreement after the next deposit, and accrued debt in position health.
