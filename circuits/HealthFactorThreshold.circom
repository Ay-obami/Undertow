pragma circom 2.1.9;

include "poseidon.circom";
include "comparators.circom";
include "bitify.circom";

// ============================================================================
// HealthFactorThreshold
//
// Proves "my position's health factor is >= threshold" without revealing the
// underlying collateral or debt values.
//
//   healthFactor = (collateralValueRay * liquidationThreshold) / debtValueRay
//
// To avoid division inside the circuit (expensive + awkward to constrain),
// the check is rearranged to a pure multiplication comparison:
//
//   collateralValueRay * liquidationThreshold  >=  thresholdRay * debtValueRay
//
// Binding: collateralValueRay/debtValueRay are private, but the circuit also
// proves they hash (via Poseidon) to a public `commitment`. Without this, a
// prover could fabricate any collateral/debt pair satisfying the inequality —
// the commitment ties the proof to a *specific* value pair that something
// else (e.g. a value posted on-chain at position-open time) can be checked
// against. Wiring that commitment into the Pool itself is a follow-up (see
// circuits/README.md) — this circuit is deliberately self-contained so it
// can be tested and verified independently of that integration.
//
// Bit widths: RAY-scaled USD values (1e18 per unit) for positions up to
// ~$1 trillion fit comfortably under 100 bits; liquidationThreshold and
// thresholdRay are RAY-scaled ratios that never exceed 1e18 (~60 bits) by
// construction elsewhere in the protocol, but are still range-checked here
// rather than trusted, since a malicious prover controls every circuit
// input. Both product terms then fit under ~164 bits — nowhere near the
// ~254-bit BN254 field size — so there is no wraparound/overflow way to
// falsely satisfy the inequality.
// ============================================================================

template HealthFactorThreshold() {
    // ── Private inputs ──────────────────────────────────────────────
    signal input collateralValueRay; // RAY-scaled USD value of locked collateral
    signal input debtValueRay;       // RAY-scaled USD value of outstanding debt
    signal input salt;               // blinds the commitment against brute-force guessing

    // ── Public inputs ───────────────────────────────────────────────
    signal input commitment;          // Poseidon(collateralValueRay, debtValueRay, salt)
    signal input liquidationThreshold; // RAY-scaled, e.g. 0.85e18 for an 85% LT reserve
    signal input thresholdRay;         // RAY-scaled minimum health factor being proven, e.g. 1e18

    // ── 1. Range-check every value-bearing input ────────────────────
    // Without these, a malicious prover could pick huge values that wrap
    // around the field modulus and satisfy the inequality falsely.
    component collateralBits = Num2Bits(100);
    collateralBits.in <== collateralValueRay;

    component debtBits = Num2Bits(100);
    debtBits.in <== debtValueRay;

    component ltBits = Num2Bits(64);
    ltBits.in <== liquidationThreshold;

    component thresholdBits = Num2Bits(64);
    thresholdBits.in <== thresholdRay;

    // ── 2. Commitment binding ────────────────────────────────────────
    component hasher = Poseidon(3);
    hasher.inputs[0] <== collateralValueRay;
    hasher.inputs[1] <== debtValueRay;
    hasher.inputs[2] <== salt;
    hasher.out === commitment;

    // ── 3. Health factor >= threshold, as a multiplication comparison ─
    signal lhs; // collateralValueRay * liquidationThreshold
    signal rhs; // thresholdRay * debtValueRay
    lhs <== collateralValueRay * liquidationThreshold;
    rhs <== thresholdRay * debtValueRay;

    component gte = GreaterEqThan(180); // 100 + 64 + margin bits, covers both products
    gte.in[0] <== lhs;
    gte.in[1] <== rhs;
    gte.out === 1;
}

component main {public [commitment, liquidationThreshold, thresholdRay]} = HealthFactorThreshold();
