# Undertow — Flare lending research fork

Undertow is the Flare/Coston2 adaptation of [Lending_Borrowing_Protocol](https://github.com/Ay-obami/Lending_Borrowing_Protocol). The latter is the recommended canonical home for shared lending-core maintenance; this repository preserves Flare integration and experimental hackathon work. Neither repository is an independently audited or production-ready lending market.

Supported development scope: direct-wallet lending calls and test environments. The standalone ZK verifier and ERC-4337 paymasters are research demos, excluded from the supported lending deployment path. See `SCOPE.md`.

Monorepo — Foundry contracts + React frontend as separate workspaces.

```
lending-protocol/
├── contracts/          ← Foundry project
│   ├── src/
│   │   ├── interfaces/         IPool, IInterestStrategy, IPriceOracle
│   │   ├── libraries/          DataTypes, MathLib, ReserveLib
│   │   ├── modules/            Pool (facade), SupplyModule, BorrowModule,
│   │   │                       LiquidationModule, PoolStorage,
│   │   │                       VariableInterestStrategy
│   │   ├── oracle/             ChainlinkOracle, FtsoOracle (Flare FTSOv2)
│   │   ├── account/            VerifyingPaymaster, FxrpGasPaymaster (ERC-4337)
│   │   └── zk/                 Groth16Verifier (generated), SolvencyVerifier
│   ├── test/
│   │   ├── mocks/              MockERC20, MockOracle, MockFtsoV2
│   │   └── unit/               PoolTestBase, SupplyModule.t.sol,
│   │                           BorrowModule.t.sol, LiquidationModule.t.sol,
│   │                           FtsoOracle.t.sol, FxrpReserve.t.sol,
│   │                           BugAudit.t.sol (Week 3 re-audit),
│   │                           SolvencyVerifier.t.sol (Week 4 ZK proof),
│   │                           Paymaster.t.sol (Week 5 account layer)
│   └── scripts/
│       ├── Deploy.s.sol        Local/generic deploy (mocks or Chainlink)
│       ├── DeployCoston2.s.sol Flare Coston2 deploy — FXRP + WFLR via FTSOv2
│       ├── DeployAccountLayer.s.sol  EntryPoint + factory + both paymasters
│       └── fassets/            Node/TS scripts for the full mint-FXRP-from-XRP flow
├── circuits/            ← Circom + snarkjs — health-factor-threshold ZK proof
│   ├── HealthFactorThreshold.circom
│   ├── prove.js
│   └── build/            Compiled circuit, proving/verification keys, worked example
└── frontend/           ← Vite + React + wagmi
    └── src/
        ├── lib/
        │   ├── abi.ts          Pool + ERC20 ABI (bytes32 reserve/position IDs)
        │   ├── math.ts         RAY math, rate formulas, formatting, error decoding
        │   ├── reserveId.ts    keccak256 helper matching Pool.getReserveId()
        │   └── wagmi.ts        Coston2 chain config + POOL_ADDRESS
        ├── services/
        │   └── poolService.ts  All contract calls (bytes32-aware)
        ├── hooks/
        ├── pages/
        └── types/
```

## Quick start

For full step-by-step deployment walkthroughs (prerequisites, exact
commands, verification, troubleshooting), see **`DEPLOY_LOCAL.md`** (Anvil,
for development/testing) and **`DEPLOY_TESTNET.md`** (Flare Coston2). What
follows here is the short version.

### Contracts

Use Foundry v1.8.3, matching CI. From the repository root, initialize the
pinned dependencies before building:

```bash
git submodule update --init --recursive
cd contracts
forge fmt --check
forge build
forge test
# Local node
anvil &
forge script scripts/Deploy.s.sol --rpc-url localhost --broadcast
```

**Deploying to Flare Coston2** (FXRP + WFLR reserves, priced via FTSOv2):

```bash
forge script scripts/DeployCoston2.s.sol --rpc-url coston2 --broadcast
```

Needs a funded deployer (get testnet C2FLR from the
[Coston2 faucet](https://faucet.flare.network/coston2)). See
`contracts/scripts/fassets/README.md` for how to also mint FXRP from real XRP —
though on Coston2 you can just grab testnet FXRP from the same faucet.

### Frontend

```bash
cd frontend
cp .env.example .env   # fill in VITE_POOL_ADDRESS etc.
npm install
npm run dev
```

## Architecture

The monolithic `Pool.sol` has been split into focused modules:

| Module | Responsibility |
|---|---|
| `PoolStorage` | All storage slots + shared getters — no business logic |
| `SupplyModule` | `deposit` / `withdraw` |
| `BorrowModule` | `borrow` / `repay` |
| `LiquidationModule` | `liquidate` / `checkPositionHealth` |
| `Pool` | Thin facade — routes calls, owns `addReserve` and admin |
| `VariableInterestStrategy` | Two-slope interest model (swappable per reserve) |
| `ChainlinkOracle` | Chainlink-backed price oracle with decimal normalisation |
| `FtsoOracle` | Flare FTSOv2-backed price oracle — drop-in `IPriceOracle`, used for FXRP/WFLR on Coston2/Songbird |

## Bug fixes from original

| Bug | Fix |
|---|---|
| `Pool.sol` imported oracle from `test/Mocks/` | Proper `ChainlinkOracle` in `src/oracle/` |
| Chainlink 8-decimal price used as RAY (1e18) | `MathLib.chainlinkToRay()` normalises correctly |
| `liquidationBonus` stored but never applied | `LiquidationModule` applies bonus to seized collateral |
| `getUserBorrowBalance` mutated state | Pure `view` — reads index without writing |
| Supply cap checked before index update | `updateIndexes()` called first in `deposit()` |
| Closed positions left empty slots in array | `getUserPositions` filters `isOpen == false` |
| String reserve keys on every call | `bytes32` IDs computed once with `keccak256` |
| `checkPositionHealth` read a stale borrow index between reserve interactions | `ReserveLib.previewBorrowIndex()` — non-mutating peek, always current |

See `AUDIT_WEEK3.md` for the full re-audit writeup (all four bugs the PRD
calls out as previously self-audited, re-verified with tests against this
ported codebase).

## Experimental arithmetic proofs (ZK)

The circuit proves a threshold inequality for private, self-reported collateral/debt values behind a Poseidon commitment. It does not prove a user's actual Pool solvency: no Pool position, account ownership, chain, timestamp, current prices, or current debt index is authenticated. Proofs can be copied and replayed. `SolvencyProven` identifies the transaction caller, not an authenticated position owner. Do not use the verifier or its events for lending authorization, higher LTV, collateral release, liquidation decisions, or current-solvency badges.

Generate the standalone demo with:

```bash
cd circuits
npm install
node prove.js <collateralValueRay> <debtValueRay> <salt> <liquidationThreshold> <thresholdRay>
```

prints a commitment plus ready-to-paste calldata for
`SolvencyVerifier.verifySolvency(...)`. See `circuits/README.md` for the full
writeup, including an important caveat: the trusted setup in this repo is
dev-scale (single local contribution), fine for a hackathon demo but not for
anything gating real funds without redoing it against a public ceremony.

## Experimental ERC-4337 account layer

`src/account/VerifyingPaymaster.sol` sponsors gas for UserOperations
pre-approved by an off-chain signer; `src/account/FxrpGasPaymaster.sol`
extends it to bill the sponsored gas back to the user in FXRP afterward
(priced via `FtsoOracle`, same as reserve pricing). Neither existed in this
codebase before — the PRD describes the paymaster as "reused from prior
work," but only an empty `lib/account-abstraction` submodule reference was
actually present, so this was built fresh against
[eth-infinitism's v0.9 account-abstraction](https://github.com/eth-infinitism/account-abstraction)
rather than reconnected.

`contracts/scripts/DeployAccountLayer.s.sol` is retained as an experimental deployment artifact. It creates a fresh EntryPoint, account factory and funded paymasters; this does not establish bundler support or absence of a canonical EntryPoint deployment. It is excluded from the supported lending deployment instructions.

`test/unit/Paymaster.t.sol` instantiates a real EntryPoint and uses real paymaster ECDSA signatures, but impersonates the EntryPoint for direct callback tests. It does not execute `handleOps`, validate a real account signature/nonce, prove gas settlement, or establish bundler/frontend interoperability. This is not a verified gasless deposit/repay lifecycle.

The FXRP paymaster performs post-execution billing without escrow or a validation-time maximum-charge reserve. Missing/revoked allowance, spent balances, a reverted approval batch, or oracle failure can make billing revert while sponsorship still consumes native funds. Keep both paymasters outside the supported deployment path and do not fund them as a public service.

## Frontend fixes from original

The frontend's `lib/abi.ts`, `lib/math.ts`, and `lib/wagmi.ts` were imported
throughout the codebase (`services/poolService.ts`, every hook) but didn't
exist in the repo — the app couldn't build. Beyond creating those, two
hooks had genuine bugs from an incomplete bytes32-ID migration (visible in
`poolService.ts`'s own header comment describing the migration as done):

| Bug | Fix |
|---|---|
| `lib/abi.ts`, `lib/math.ts`, `lib/wagmi.ts` referenced but missing entirely | Created, matching every existing import site exactly |
| `useContract`'s `deposit`/`withdraw`/`borrow`/`repay` passed raw reserve **name strings** to a service layer expecting **bytes32 IDs** | Convert via `computeReserveId()` before calling `poolService` |
| `useHealthFactor` called a `getReserveData` function that no longer exists, with name-string args | Fixed to call `getReserve` with the position's bytes32 `collateralReserveId`/`borrowReserveId` |
| `usePositions` built its reserve lookup map keyed by a `raw.collateralAsset` string field that isn't on the actual `Position` struct | Keyed by `raw.id` (bytes32) instead, resolving display names from the matching reserve |

The original author reported clean TypeScript and Vite builds for that revision. Run the current frontend checks after configuration or code changes; those historical results do not establish current behavior.


## Explicit experimental deployment opt-in

The account deployment script aborts before configuration reads or broadcast unless `ENABLE_EXPERIMENTAL_ACCOUNT_LAYER=true`. Both paymaster deposits default to zero. For an isolated experiment, explicitly opt in:

```bash
ENABLE_EXPERIMENTAL_ACCOUNT_LAYER=true \
FTSO_ORACLE=0x... VERIFYING_SIGNER=0x... \
forge script scripts/DeployAccountLayer.s.sol --rpc-url coston2
```

This command simulates and does not broadcast. `EXPERIMENTAL_PAYMASTER_DEPOSIT` is an optional amount in native-token wei deposited into **each** paymaster; leave it unset for zero funding. Opt-in does not resolve the lifecycle or recovery limitations above.

## Final lending audit workstream

Native-decimal valuation, reserved collateral cash, bounded reserve configuration, full-precision arithmetic, oracle boundary checks and stable position IDs are covered by regression tests. The frontend reads accrued per-position debt and verifies full repayment after receipt. CI runs contract formatting/build/tests, fail-on-revert stateful invariants, frontend tests and a production client build.

See [lending policy](contracts/LENDING_POLICY.md), [oracle validation](contracts/ORACLE_VALIDATION.md) and [fork validation](contracts/FORK_VALIDATION.md) for behavior, reproducible checks and limitations. Use a fresh deployment for these changes.
