# Scope and repository ownership

Recommended canonical repository: `Ay-obami/Lending_Borrowing_Protocol`, for the shared modular lending core, generic Chainlink adapter and direct-wallet frontend. Its smaller feature surface makes shared accounting fixes and regression maintenance easier to review. Undertow remains the separate Flare/Coston2 integration and experimental hackathon fork. This recommendation does not archive, delete, privatize or change either repository's default branch.

Shared fixes should be reviewed in the canonical repository and ported explicitly to Undertow with tests; no automatic parity is implied. Undertow's Flare oracle, registry deployment, FAssets scripts, circuit and account layer are fork-specific responsibilities.

## Supported development scope

- Local mock deployments and direct-wallet supply, withdrawal, borrowing, repayment and liquidation flows.
- Flare/Coston2 core deployment scripts as a testnet candidate, requiring simulation and live configuration checks; no deployed address or successful live run is claimed here.
- Conventional exact-transfer ERC20 assets within documented token/accounting restrictions. Review `contracts/TOKEN_SUPPORT.md` and the accompanying accounting/boundary notes when present.

## Experimental and historical scope

- `circuits/` and `contracts/src/zk/`: standalone self-reported arithmetic proof demos; no Pool-bound, user-authenticated or current-solvency claim. Do not gate funds or lending eligibility with these proofs/events.
- `contracts/src/account/` and `contracts/scripts/DeployAccountLayer.s.sol`: callback-level paymaster experiments. No verified `handleOps` lifecycle, signer service, bundler or frontend account integration. Post-execution FXRP collection is not guaranteed.
- `SUBMISSION.md` and `AUDIT_WEEK3.md`: historical hackathon documents preserved with archival labels. Their test counts, timelines and deployment TODOs are not current verification evidence.

This scoped remediation is not a full security audit and does not establish production readiness. Tests establish only the exercised scenarios at the recorded revision and dependency set.
