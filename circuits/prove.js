// Generates a full "prove my health factor" flow end to end:
//   1. Compute the Poseidon commitment for (collateralValueRay, debtValueRay, salt)
//   2. Generate the witness
//   3. Generate the Groth16 proof
//   4. Print ready-to-paste Solidity calldata for SolvencyVerifier.verifySolvency
//
// Usage:
//   node prove.js <collateralValueRay> <debtValueRay> <salt> <liquidationThreshold> <thresholdRay>
//
// Example (30,000 collateral, 20,000 debt, 85% LT, proving HF >= 1):
//   node prove.js 30000000000000000000000 20000000000000000000000 123456789 850000000000000000 1000000000000000000

import { buildPoseidon } from "circomlibjs";
import * as snarkjs from "snarkjs";
import { writeFileSync } from "fs";

async function main() {
  const [collateralValueRay, debtValueRay, salt, liquidationThreshold, thresholdRay] =
    process.argv.slice(2);

  if (!thresholdRay) {
    console.error(
      "Usage: node prove.js <collateralValueRay> <debtValueRay> <salt> <liquidationThreshold> <thresholdRay>"
    );
    process.exit(1);
  }

  const poseidon = await buildPoseidon();
  const F = poseidon.F;
  const commitmentHash = poseidon([BigInt(collateralValueRay), BigInt(debtValueRay), BigInt(salt)]);
  const commitment = F.toObject(commitmentHash).toString();

  const input = {
    collateralValueRay,
    debtValueRay,
    salt,
    commitment,
    liquidationThreshold,
    thresholdRay,
  };

  console.log("Commitment:", commitment);
  console.log("(Post this commitment publicly / on-chain ahead of time so the");
  console.log(" proof is checkable against a value you committed to in advance.)\n");

  const { proof, publicSignals } = await snarkjs.groth16.fullProve(
    input,
    "build/HealthFactorThreshold_js/HealthFactorThreshold.wasm",
    "build/HealthFactorThreshold_final.zkey"
  );

  writeFileSync("build/proof_last.json", JSON.stringify(proof, null, 2));
  writeFileSync("build/public_last.json", JSON.stringify(publicSignals, null, 2));

  const calldata = await snarkjs.groth16.exportSolidityCallData(proof, publicSignals);
  console.log("Solidity calldata for SolvencyVerifier.verifySolvency(pA, pB, pC, commitment, liquidationThreshold, thresholdRay):\n");
  console.log(calldata);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
