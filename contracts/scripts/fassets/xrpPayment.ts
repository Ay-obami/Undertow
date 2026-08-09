// Step 2 of 3 in the FXRP mint flow: send the underlying XRP payment on the
// XRP Ledger testnet, carrying the payment reference from Step 1 as a memo.
//
// Adapted from Flare's guide (see reserveCollateral.ts header) to plain
// xrpl.js. Fill in AGENT_ADDRESS / AMOUNT_XRP / PAYMENT_REFERENCE from the
// output of `npm run reserve` before running this.
//
// Usage:
//   npm run pay

import "dotenv/config";
import { Client, Wallet, xrpToDrops, type Payment, type TxResponse } from "xrpl";

const AGENT_ADDRESS = process.env.FXRP_AGENT_ADDRESS ?? ""; // from reserveCollateral.ts output
const AMOUNT_XRP = process.env.FXRP_PAYMENT_AMOUNT ?? "";   // from reserveCollateral.ts output
const PAYMENT_REFERENCE = process.env.FXRP_PAYMENT_REFERENCE ?? ""; // from reserveCollateral.ts output

const XRPL_TESTNET_WS = "wss://s.altnet.rippletest.net:51233";

async function sendPaymentWithReference() {
  if (!AGENT_ADDRESS || !AMOUNT_XRP || !PAYMENT_REFERENCE) {
    throw new Error(
      "Set FXRP_AGENT_ADDRESS, FXRP_PAYMENT_AMOUNT, FXRP_PAYMENT_REFERENCE " +
        "(from reserveCollateral.ts output) in your .env before running this."
    );
  }

  const client = new Client(XRPL_TESTNET_WS);
  await client.connect();

  const wallet = Wallet.fromSeed(process.env.XRPL_TESTNET_SEED!);

  const paymentTx: Payment = {
    TransactionType: "Payment",
    Account: wallet.classicAddress,
    Destination: AGENT_ADDRESS,
    Amount: xrpToDrops(AMOUNT_XRP),
    Memos: [{ Memo: { MemoData: PAYMENT_REFERENCE } }],
  };

  console.log("Submitting payment:", paymentTx);

  const prepared = await client.autofill(paymentTx);
  const signed = wallet.sign(prepared);
  const result: TxResponse = await client.submitAndWait(signed.tx_blob);

  console.log("\n── Save this for Step 3 (executeMinting.ts) ───────");
  console.log("Transaction hash (transactionId):", signed.hash);
  console.log("Explorer:", `https://testnet.xrpl.org/transactions/${signed.hash}`);
  console.log("Result:", result);

  await client.disconnect();
}

sendPaymentWithReference().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
