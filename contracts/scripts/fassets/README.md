# Minting FXRP on Coston2

Two ways to get testnet FXRP, in order of how much of the real flow you want to exercise:

## Fast path — just testing the pool

**On Coston2, testnet FXRP is available directly from the
[Coston2 faucet](https://faucet.flare.network/coston2) — no minting required.**
If you just want to deposit/borrow against FXRP in this protocol, grab some C2FLR
and FXRP from the faucet and skip straight to `scripts/DeployCoston2.s.sol`.

## Full path — mint FXRP from real XRP

This is the flow an actual user goes through post-hackathon (and on mainnet,
where there's no faucet). It has four steps, and steps 2–3 happen *outside*
this repo (on the XRP Ledger and via Flare's Data Connector), so it can't be
a single Foundry script — it's three small Node/TS scripts run in sequence,
matching [Flare's own guide](https://dev.flare.network/fassets/developer-guides/fassets-mint).

```
1. reserveCollateral.ts   Reserve collateral from an agent (on-chain, Flare)
2. xrpPayment.ts          Pay the agent in XRP, with a payment reference (XRPL)
3. (wait for FDC round)   Flare Data Connector attests the payment (automatic)
4. executeMinting.ts      Submit the FDC proof, receive FXRP (on-chain, Flare)
```

### Setup

```bash
cd scripts/fassets
npm install
cp .env.example .env
# fill in RPC_URL_COSTON2, PRIVATE_KEY, XRPL_TESTNET_SEED
```

Get a Coston2 deployer key funded via the [Coston2 faucet](https://faucet.flare.network/coston2),
and an XRPL testnet wallet + funds via the [XRP Testnet Faucet](https://xrpl.org/resources/dev-tools/xrp-faucets).

### Run it

```bash
npm run reserve
# copy the printed agent address / amount / payment reference / reservation id into .env

npm run pay
# copy the printed XRPL transaction hash into .env as FXRP_XRPL_TX_ID

# wait a few minutes for the FDC voting round covering your payment to finalize,
# then look up the round id (see https://dev.flare.network/fdc/overview) and set
# FXRP_FDC_ROUND_ID in .env

npm run execute
# FXRP lands in your wallet
```

### Notes

- **Payment timeframe:** the `CollateralReserved` event from step 1 includes
  `lastUnderlyingBlock` / `lastUnderlyingTimestamp` — your XRPL payment must land
  before *both* deadlines, or the agent can default your reservation and you lose
  the collateral reservation fee.
- **Collateral Reservation Fee (CRF):** paid in C2FLR when reserving, non-refundable
  even if minting fails — this is what compensates the agent/pool for locking collateral
  during your payment window.
- These scripts are intentionally minimal (hand-trimmed ABI fragments, no retry/backoff
  logic) — treat them as a working reference for the flow, not production infrastructure.
  For a keeper-grade version, see Flare's [fasset-bots](https://github.com/flare-foundation/fasset-bots) repo.
