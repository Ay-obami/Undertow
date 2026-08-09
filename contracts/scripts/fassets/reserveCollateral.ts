// Step 1 of 3 in the FXRP mint flow: reserve collateral from a suitable agent.
//
// Adapted from Flare's own hardhat-based guide
// (https://dev.flare.network/fassets/developer-guides/fassets-mint) to plain
// ethers.js, since this repo's contracts are Foundry-based rather than
// Hardhat. Behaviour and call sequence match the official guide exactly.
//
// Usage:
//   cp .env.example .env   # fill in RPC_URL_COSTON2 + PRIVATE_KEY
//   npm install
//   npm run reserve

import "dotenv/config";
import { JsonRpcProvider, Wallet, formatEther } from "ethers";
import { getAssetManagerFXRP } from "./fassetsCommon.js";

const LOTS_TO_MINT = 1;
const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";

async function findBestAgent(assetManager: any, minAvailableLots = 1) {
  const { agents } = await assetManager.getAvailableAgentsDetailedList(0, 100);

  let candidates = agents.filter((a: any) => a.freeCollateralLots > minAvailableLots);
  if (candidates.length === 0) return undefined;

  candidates.sort((a: any, b: any) => Number(a.feeBIPS) - Number(b.feeBIPS));

  for (const candidate of candidates) {
    const info = await assetManager.getAgentInfo(candidate.agentVault);
    if (Number(info.status) === 0) return candidate.agentVault; // 0 = NORMAL
  }
  return undefined;
}

async function main() {
  const provider = new JsonRpcProvider(process.env.RPC_URL_COSTON2);
  const wallet = new Wallet(process.env.PRIVATE_KEY!, provider);

  const assetManager = await getAssetManagerFXRP(provider, wallet);

  const agentVault = await findBestAgent(assetManager, LOTS_TO_MINT);
  if (!agentVault) throw new Error("No suitable agent found with enough free collateral lots");
  console.log("Selected agent vault:", agentVault);

  const agentInfo = await assetManager.getAgentInfo(agentVault);
  const fee = await assetManager.collateralReservationFee(LOTS_TO_MINT);
  console.log("Collateral reservation fee (C2FLR):", formatEther(fee));

  const tx = await assetManager.reserveCollateral(
    agentVault,
    LOTS_TO_MINT,
    agentInfo.feeBIPS,
    ZERO_ADDRESS, // not using an executor
    { value: fee }
  );
  const receipt = await tx.wait();
  console.log("reserveCollateral tx:", receipt.hash);

  const event = receipt.logs
    .map((log: any) => {
      try {
        return assetManager.interface.parseLog(log);
      } catch {
        return null;
      }
    })
    .find((e: any) => e?.name === "CollateralReserved");

  if (!event) throw new Error("CollateralReserved event not found in receipt");

  const { collateralReservationId, valueUBA, feeUBA, paymentAddress, paymentReference } = event.args;
  const decimals = await assetManager.assetMintingDecimals();
  const totalUBA = BigInt(valueUBA) + BigInt(feeUBA);
  const totalXRP = Number(totalUBA) / 10 ** Number(decimals);

  console.log("\n── Save these for the next two steps ──────────────");
  console.log("Collateral reservation id:", collateralReservationId.toString());
  console.log("Pay to (agent XRPL address):", paymentAddress);
  console.log("Payment reference (memo):   ", paymentReference);
  console.log(`Amount to pay:                ${totalXRP} XRP`);
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
