# Reserve token assumptions

Reserve assets must have ordinary ERC-20 balances and exact transfers in both directions. Fee-on-transfer, rebasing and arbitrary callback token behavior are unsupported.

Deposits, repayments and liquidation payments now compare the pool balance before and after `safeTransferFrom`. If the observed increase differs from the credited or repaid amount, `UnexpectedTokenReceipt(token, expected, received)` reverts the entire transaction. Accounting changes, collateral releases and the token transfer roll back together.

This check protects incoming accounting from short or excessive receipts. It does not certify a token's implementation, inspect outgoing recipient receipts, prevent a token from lying about balances, or provide general callback/reentrancy protection. Reserve administration must review token behavior before listing. Interest accrual, aggregate reserve accounting and liquidation economics require separate review.

`test/unit/ExactReceipt.t.sol` covers fuzzed short deposits, partial/full debt repayment, liquidation rollback and a successful exact-transfer flow.
