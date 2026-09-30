> Archived hackathon draft. Claims and TODOs below reflect the original submission planning, not current deployment evidence. ZK proves only self-reported arithmetic; the paymaster tests do not execute an EntryPoint `handleOps` lifecycle. Neither experiment is in the supported lending scope. See `SCOPE.md` and the current README.

# FXRP Private Lending Market — Submission

*Draft — items marked `[TODO]` need something only you can supply (a live
deploy, a recorded demo, real tester feedback). Everything else is filled in
from the actual codebase, not aspirationally.*

## Project name, target user, and short description

**FXRP Private Lending Market** — a FAssets-native lending and borrowing
protocol on Flare, with FTSO-based pricing and an optional zero-knowledge
solvency proof.

Built for three overlapping users: XRP holders who want DeFi yield/borrowing
without leaving Flare's trust-minimized FAssets custody model; existing DeFi
users who want FXRP as native collateral priced off Flare's own oracle
rather than a third-party feed; and privacy-conscious borrowers who want to
prove they're solvent without broadcasting their exact position size.

## Demo video / working app link

`[TODO — record a short walkthrough: connect wallet → deposit FXRP →
borrow WFLR → show health factor → optionally generate a ZK solvency proof.
Link it here.]`

## GitHub repo with clear README

`[TODO — link the repo]`. `README.md` covers quick start (contracts +
frontend), architecture, the bug-fix history, the ZK solvency proof flow,
and the gasless-transaction account layer. Each major addition also has its
own focused doc: `AUDIT_WEEK3.md` (liquidation re-audit), `circuits/README.md`
(ZK circuit + trusted-setup caveats), `scripts/fassets/README.md` (minting
FXRP from real XRP).

## Explanation of Flare integration

**FTSO (Flare Time Series Oracle):** `src/oracle/FtsoOracle.sol` replaces
the base codebase's Chainlink oracle for Coston2/Songbird deployments,
reading Flare's FTSOv2 block-latency feeds via `ContractRegistry.getTestFtsoV2()`
and normalizing each feed's native decimals to the protocol's internal RAY
(1e18) scale. Every price used for collateral valuation, borrow limits, and
liquidation triggers on Flare comes from FTSO — not a third-party feed. Feed
IDs are registered per-reserve (`FtsoOracle.setFeedId`), and both `FXRP`
(priced off `XRP/USD`, since FXRP is 1:1 backed by XRP) and `WFLR` (priced
off `FLR/USD`) are wired up in `scripts/DeployCoston2.s.sol`.

**FAssets:** FXRP — the FAsset ERC20 representing trust-minimized XRP on
Flare — is a first-class reserve, resolved at deploy time via
`ContractRegistry.getAssetManagerFXRP().fAsset()` rather than a hardcoded
address (so the same script works if that address ever changes). The full
mint-FXRP-from-real-XRP flow (reserve collateral → pay XRP on the XRPL
testnet → Flare Data Connector attestation → execute minting) is implemented
in `scripts/fassets/` as three Node/TS scripts, matching Flare's own
documented flow. For just trying the pool, testnet FXRP is available
directly from the [Coston2 faucet](https://faucet.flare.network/coston2) —
no minting required.

## Explicit before/after split

See the PRD's own Section 7 for the original reused/new-build split. What
was *actually* found already built vs. genuinely new, once the ported repo
was in hand:

| Area | Expected (per PRD) | Actually found | What was built |
|---|---|---|---|
| Lending core (interest model, liquidation engine) | Reused | Present, mostly correct | Re-audited (see below) |
| Oracle | Chainlink → swap to FTSO | Chainlink present | `FtsoOracle.sol` added alongside it |
| FXRP support | New build | Not present | Added (`DeployCoston2.s.sol`, `FxrpReserve.t.sol`) |
| ZK solvency proof | New build | Not present | Circom circuit + Groth16 verifier, from scratch |
| ERC-4337 paymaster | **Reused** | **Not present** (empty submodule reference only) | Built from scratch against eth-infinitism v0.9 |
| Frontend | Reused, adapt to new contracts | **Didn't build** — referenced `lib/abi.ts`/`lib/math.ts`/`lib/wagmi.ts` that didn't exist, plus two hooks with genuine bugs from a half-finished bytes32-ID migration | Created the missing files; fixed the two broken hooks |

**Liquidation re-audit** (the four bugs the PRD calls previously
self-audited): missing transfer in repay, unapplied liquidation bonus, and
oracle decimal mismatch were already fixed in the ported code — regression
tests were added to lock that in (`test/unit/BugAudit.t.sol`). Stale
borrow-index health checks was **still present** — `checkPositionHealth`
read a borrow index that only updates on state-changing calls, so a
position accruing interest between two calls could look healthy
indefinitely. Fixed via `ReserveLib.previewBorrowIndex` (see
`AUDIT_WEEK3.md` for the full writeup).

## Contract addresses on Coston2/Songbird

`[TODO — fill in after running the deploy scripts against Coston2]`

```bash
cd contracts
forge script scripts/DeployCoston2.s.sol --rpc-url coston2 --broadcast
# copy the logged addresses below

FTSO_ORACLE=<from above> forge script scripts/DeployAccountLayer.s.sol --rpc-url coston2 --broadcast
```

| Contract | Address |
|---|---|
| Pool | `[TODO]` |
| FtsoOracle | `[TODO]` |
| VariableInterestStrategy | `[TODO]` |
| FXRP (FAsset token) | `[TODO]` |
| WFLR | `[TODO]` |
| EntryPoint | `[TODO]` |
| SimpleAccountFactory | `[TODO]` |
| VerifyingPaymaster | `[TODO]` |
| FxrpGasPaymaster | `[TODO]` |
| SolvencyVerifier | `[TODO — deploy separately: `new SolvencyVerifier(groth16VerifierAddr)`, see circuits/README.md]` |

Mainnet: not deployed (out of scope per PRD Section 3 non-goals unless
pursuing the optional traction-demo stretch).

## Short roadmap / next steps

- **Bind ZK commitments to real positions.** The solvency circuit currently
  proves a claim about a `(collateral, debt)` pair behind a self-reported
  commitment — it doesn't yet know about actual `Pool` positions. Wiring
  that in means computing and storing a commitment on `Position` at
  borrow/repay time (see `circuits/README.md`'s integration note).
- **Production trusted setup.** The circuit's Groth16 setup is a single
  local dev contribution — fine for this demo, not for anything gating real
  funds. Swap in a public ceremony transcript before any deployment beyond
  a hackathon/testnet context.
- **Mainnet-grade FTSO reads.** `FtsoOracle` uses `TestFtsoV2Interface`
  (free `view` reads, intended for testnet). A mainnet deployment should
  switch to the payable `FtsoV2Interface` and handle the per-read fee.
- **(Stretch, per PRD) FCC-based private liquidation keeper** — not started;
  scoped as optional in the PRD and left that way here.
- Additional collateral assets beyond FXRP/WFLR.

## Early user feedback / tester notes

`[TODO — per PRD Section 4's success metric: get at least one external
tester through a full deposit → borrow → repay cycle and note what they hit]`
