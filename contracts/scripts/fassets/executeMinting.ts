// Step 3 of 3 in the FXRP mint flow: fetch a Flare Data Connector (FDC)
// Merkle proof of the XRPL payment from Step 2, then call executeMinting on
// the AssetManager to actually receive FXRP.
//
// Adapted from Flare's guide (see reserveCollateral.ts header) to plain
// ethers.js. The FDC round id only becomes known once the voting round that
// covers your payment's timestamp finalizes — typically a few minutes after
// the XRPL payment. If `get-proof-round-id-bytes` 404s, the round hasn't
// finalized yet; wait and retry.
//
// Usage:
//   npm run execute

import "dotenv/config";
import { JsonRpcProvider, Wallet } from "ethers";
import { getAssetManagerFXRP } from "./fassetsCommon.js";

const COLLATERAL_RESERVATION_ID = process.env.FXRP_COLLATERAL_RESERVATION_ID ?? "";
const TRANSACTION_ID = process.env.FXRP_XRPL_TX_ID ?? ""; // hash from xrpPayment.ts output
const TARGET_ROUND_ID = process.env.FXRP_FDC_ROUND_ID ?? ""; // see fdc round-id lookup below

const { COSTON2_DA_LAYER_URL, VERIFIER_URL_TESTNET, VERIFIER_API_KEY_TESTNET } = process.env;

async function prepareFdcRequest(transactionId: string) {
  const requestBody = { transactionId, inUtxo: "0", utxo: "0" };
  const url = `${VERIFIER_URL_TESTNET}/verifier/xrp/Payment/prepareRequest`;

  const res = await fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-API-KEY": VERIFIER_API_KEY_TESTNET ?? "",
    },
    body: JSON.stringify({
      attestationType: encodeAttestationType("Payment"),
      sourceId: encodeAttestationType("testXRP"),
      requestBody,
    }),
  });
  if (!res.ok) throw new Error(`prepareRequest failed: ${res.status} ${await res.text()}`);
  return res.json();
}

function encodeAttestationType(value: string): string {
  // Left-padded, 0x-prefixed 32-byte hex, per FDC's fixed-width string encoding.
  return "0x" + Buffer.from(value, "utf8").toString("hex").padEnd(64, "0");
}

async function getProof(votingRoundId: string) {
  const request = await prepareFdcRequest(TRANSACTION_ID);

  const res = await fetch(`${COSTON2_DA_LAYER_URL}/api/v0/fdc/get-proof-round-id-bytes`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-API-KEY": VERIFIER_API_KEY_TESTNET ?? "",
    },
    body: JSON.stringify({ votingRoundId, requestBytes: request.abiEncodedRequest }),
  });
  if (!res.ok) {
    throw new Error(
      `get-proof-round-id-bytes failed (${res.status}) — the voting round may not have ` +
        `finalized yet. Wait a few minutes after the XRPL payment and retry. ${await res.text()}`
    );
  }
  return res.json();
}

async function main() {
  if (!COLLATERAL_RESERVATION_ID || !TRANSACTION_ID || !TARGET_ROUND_ID) {
    throw new Error(
      "Set FXRP_COLLATERAL_RESERVATION_ID (from reserveCollateral.ts), " +
        "FXRP_XRPL_TX_ID (from xrpPayment.ts), and FXRP_FDC_ROUND_ID in your .env."
    );
  }

  const provider = new JsonRpcProvider(process.env.RPC_URL_COSTON2);
  const wallet = new Wallet(process.env.PRIVATE_KEY!, provider);
  const assetManager = await getAssetManagerFXRP(provider, wallet);

  const proof = await getProof(TARGET_ROUND_ID);

  const tx = await assetManager.executeMinting(
    { merkleProof: proof.proof, data: proof.response },
    COLLATERAL_RESERVATION_ID
  );
  const receipt = await tx.wait();

  console.log("executeMinting tx:", receipt.hash);
  console.log("FXRP should now be in your wallet — check balance via the FXRP token address.");
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
