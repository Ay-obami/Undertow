# Solvency proof circuit — Week 4

Proves **"my position's health factor is ≥ some threshold"** without
revealing the underlying collateral or debt amounts on-chain.

## How it works

```
health factor = (collateralValueRay * liquidationThreshold) / debtValueRay
```

The circuit avoids division (expensive and awkward to constrain in Circom)
by rearranging the check into a pure multiplication comparison:

```
collateralValueRay * liquidationThreshold  >=  thresholdRay * debtValueRay
```

**Private inputs:** `collateralValueRay`, `debtValueRay`, `salt`
**Public inputs:** `commitment`, `liquidationThreshold`, `thresholdRay`

The circuit also proves `commitment == Poseidon(collateralValueRay, debtValueRay, salt)`.
Without this, a prover could invent any collateral/debt pair that happens to
satisfy the inequality — the commitment ties the proof to one specific,
pre-committed value pair. See "Integration note" below for what this is
*for* — on its own it just proves the pair behind a given commitment
satisfies the threshold.

All value-bearing inputs are range-checked (100 bits for RAY-scaled USD
values, up to ~$1 trillion positions; 64 bits for the RAY-scaled ratios,
which never exceed 1e18) so a malicious prover can't wrap the BN254 field
modulus to falsely satisfy the inequality.

## What's here

```
circuits/
├── HealthFactorThreshold.circom   The circuit
├── prove.js                       CLI: compute commitment → witness → proof → Solidity calldata
├── package.json
└── build/
    ├── HealthFactorThreshold.r1cs        Compiled constraint system
    ├── HealthFactorThreshold.sym
    ├── HealthFactorThreshold_js/         WASM witness calculator
    ├── HealthFactorThreshold_final.zkey  Groth16 proving key (after setup — see below)
    ├── verification_key.json
    ├── pot12_final.ptau                  Powers-of-tau (phase 1) — see caveat below
    └── input_valid.json / proof_valid.json / public_valid.json / calldata_valid.txt
                                           A worked example, also used as the
                                           test fixture in
                                           contracts/test/unit/SolvencyVerifier.t.sol
```

`contracts/src/zk/Groth16Verifier.sol` is generated directly from
`HealthFactorThreshold_final.zkey` via `snarkjs zkey export solidityverifier`
— unmodified. `contracts/src/zk/SolvencyVerifier.sol` wraps it with named
parameters and a `SolvencyProven` event.

## ⚠️ Trusted setup caveat

The Powers-of-Tau ceremony and Groth16 setup in `build/` were run **locally,
by one party (this session), for development purposes only** — a single
contribution each, no public multi-party ceremony. This is standard for
getting a circuit working end-to-end during a hackathon, but it is **not**
what you'd want backing real user funds: whoever ran that one contribution
could theoretically have retained the toxic waste and forge false proofs.

Before any deployment where a false proof would matter (i.e. if this is ever
wired into anything gating real funds — see integration note below), replace
`pot12_final.ptau` with an established public ceremony transcript — e.g.
[Hermez's / Polygon zkEVM's Powers of Tau](https://github.com/iden3/snarkjs#7-prepare-phase-2)
(reusable for any circuit up to their max constraint count) — and either run
a real multi-party `zkey contribute` ceremony or use a MPC coordination tool.
For a hackathon submission where the ZK proof is a standalone demo of the
capability rather than a funds-gating mechanism, the current setup is fine
and should be disclosed as such (which this file does).

## Reproducing / regenerating

```bash
npm install                    # circomlib, circomlibjs, snarkjs
circom HealthFactorThreshold.circom --r1cs --wasm --sym \
  -l node_modules/circomlib/circuits -o build

# Powers of tau (only needed once, or when swapping in a real ceremony file)
npx snarkjs powersoftau new bn128 12 build/pot12_0000.ptau
npx snarkjs powersoftau contribute build/pot12_0000.ptau build/pot12_0001.ptau
npx snarkjs powersoftau prepare phase2 build/pot12_0001.ptau build/pot12_final.ptau

# Circuit-specific setup
npx snarkjs groth16 setup build/HealthFactorThreshold.r1cs build/pot12_final.ptau build/HealthFactorThreshold_0000.zkey
npx snarkjs zkey contribute build/HealthFactorThreshold_0000.zkey build/HealthFactorThreshold_final.zkey
npx snarkjs zkey export verificationkey build/HealthFactorThreshold_final.zkey build/verification_key.json
npx snarkjs zkey export solidityverifier build/HealthFactorThreshold_final.zkey ../contracts/src/zk/Groth16Verifier.sol
```

## Generating a proof

```bash
node prove.js <collateralValueRay> <debtValueRay> <salt> <liquidationThreshold> <thresholdRay>

# e.g. proving HF >= 1 for a position with $30,000 collateral, $20,000 debt, 85% LT:
node prove.js 30000000000000000000000 20000000000000000000000 123456789 850000000000000000 1000000000000000000
```

This prints the commitment (post it wherever the proof needs to be checked
against later) and ready-to-paste Solidity calldata for
`SolvencyVerifier.verifySolvency(pA, pB, pC, commitment, liquidationThreshold, thresholdRay)`.

## Integration note (deliberately out of scope here)

This circuit and its verifier are self-contained — they prove/verify a
claim about a `(collateralValue, debtValue)` pair behind a given
commitment, full stop. They don't yet know anything about *this protocol's*
actual `Pool` positions.

Wiring it in for real (e.g. "prove your health factor without revealing
balances to unlock a higher LTV tier", per the PRD) needs the Pool itself to
compute and store a commitment at `borrow()`/`repay()` time — using the
position's real `collateralLocked` and current debt — so that a later
`verifySolvency` call is checkable against something the protocol itself
vouches for, not an arbitrary self-reported commitment. That's a Pool
change (new field on `Position`, updated on every state-changing call) and
is a natural Week 5/6 follow-up rather than part of the circuit/verifier
deliverable itself.
