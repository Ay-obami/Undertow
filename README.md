# Lending & Borrowing Protocol

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

```bash
cd contracts
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
`scripts/fassets/README.md` for how to also mint FXRP from real XRP —
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

## Private solvency proofs (ZK)

Users can prove "my health factor is ≥ X" without revealing their collateral
or debt amounts, via a Circom circuit + on-chain Groth16 verifier:

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

## Gasless deposit/repay (ERC-4337)

`src/account/VerifyingPaymaster.sol` sponsors gas for UserOperations
pre-approved by an off-chain signer; `src/account/FxrpGasPaymaster.sol`
extends it to bill the sponsored gas back to the user in FXRP afterward
(priced via `FtsoOracle`, same as reserve pricing). Neither existed in this
codebase before — the PRD describes the paymaster as "reused from prior
work," but only an empty `lib/account-abstraction` submodule reference was
actually present, so this was built fresh against
[eth-infinitism's v0.9 account-abstraction](https://github.com/eth-infinitism/account-abstraction)
rather than reconnected.

```bash
FTSO_ORACLE=0x... VERIFYING_SIGNER=0x... \
  forge script scripts/DeployAccountLayer.s.sol --rpc-url coston2 --broadcast
```

deploys a fresh `EntryPoint` (v0.9 is too recent to assume a canonical
pre-deployed address exists on Coston2), a `SimpleAccountFactory`, and both
paymasters, funding each with a starting EntryPoint deposit. Run after
`DeployCoston2.s.sol` — it needs that script's `FtsoOracle` address.

Tested against a real deployed `EntryPoint` (not a mock) with real ECDSA
signatures — see `test/unit/Paymaster.t.sol`.

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

Verified with `tsc --noEmit` (clean) and a full `vite build` (succeeds) —
not just read for plausibility.
