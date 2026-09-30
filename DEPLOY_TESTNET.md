# Deploying to Flare Testnet Coston2

This covers deploying the protocol to Flare's Coston2 testnet, with FXRP and
WFLR as reserves priced via FTSOv2, through direct-wallet transactions. ZK and ERC-4337 experiments are excluded from this deployment path.

**Verification status:** no live Coston2 deployment is established by this guide. Simulate first, verify chain ID 114, and inspect current registry addresses, token decimals, oracle prices, reserve configuration and owner addresses before broadcasting. Registry discovery does not guarantee compatibility or correct risk parameters. No mainnet deployment is covered.

## 1. Prerequisites

- Foundry (`forge`, `cast`) — see `DEPLOY_LOCAL.md` step 1
- A wallet with a private key you control (**not** one of Anvil's public
  test keys — this is a real, if low-value, testnet)
- Testnet C2FLR from the [Coston2 faucet](https://faucet.flare.network/coston2)
  — you'll need this for core deployment and direct-wallet transaction gas.
- (Optional, for trying deposits) Testnet FXRP — also available directly
  from the [Coston2 faucet](https://faucet.flare.network/coston2), no
  minting required. For the full mint-from-real-XRP flow instead, see
  `contracts/scripts/fassets/README.md`.

## 2. Configure your RPC endpoint and key

`contracts/foundry.toml` already has a `coston2` RPC endpoint configured:

```toml
[rpc_endpoints]
coston2 = "https://coston2-api.flare.network/ext/C/rpc"
```

You have two options for supplying your private key to `forge script`:

**Option A — pass it directly (simplest, fine for a testnet-only key):**
```bash
--private-key 0xYOUR_PRIVATE_KEY
```

**Option B — use Foundry's encrypted keystore (better if this key has any
value beyond throwaway testnet funds):**
```bash
cast wallet import coston2-deployer --interactive
# paste your private key when prompted, set a password
```
then use `--account coston2-deployer` instead of `--private-key ...` in
every command below.

## 3. Deploy the core protocol

From `contracts/`:

```bash
forge build

forge script scripts/DeployCoston2.s.sol \
  --rpc-url coston2 \
  --broadcast \
  --private-key 0xYOUR_PRIVATE_KEY
```

This script:
1. Deploys `VariableInterestStrategy` and `FtsoOracle`
2. Resolves the real FXRP token address via
   `ContractRegistry.getAssetManagerFXRP().fAsset()` and the real WFLR
   address via `ContractRegistry.getWNat()` — addresses discovered through the registry, whose current token compatibility must still be checked
3. Registers FTSOv2 feed IDs: FXRP → `XRP/USD` (FXRP is 1:1 backed by XRP),
   WFLR → `FLR/USD`
4. Deploys `Pool` and adds FXRP and WFLR as reserves (FXRP: 75% LTV, 80% liquidation threshold; WFLR: 65% LTV — see the script for full risk params)

Expect output like:

```
Pool deployed at:       0x...
FtsoOracle deployed at: 0x...
Strategy deployed at:   0x...
FXRP token address:     0x...
WFLR token address:     0x...

Get testnet FXRP + C2FLR: https://faucet.flare.network/coston2
```

**Copy every one of these addresses down** — you'll need `Pool` for the
frontend; keep the oracle and token addresses for configuration verification.

If this reverts with `DeployCoston2: FXRP not found in registry` or similar,
Flare's contract registry doesn't have that entry on the RPC you're
pointed at — double check you're actually on Coston2, not some other
network, and that the RPC endpoint is responding (`cast chain-id --rpc-url
coston2` should return `114`).

## 4. Verify on the block explorer

Every address from step 3 should be a live, verified-or-verifiable contract
at [coston2-explorer.flare.network](https://coston2-explorer.flare.network).
Search the `Pool` address and confirm:
- Contract creation transaction is present
- Two `ReserveAdded`-style events (or check via `getAllReserves`, below)

```bash
cast call <POOL_ADDRESS> "getAllReserves()" --rpc-url coston2
```
should return two tuples (FXRP and WFLR reserve configs).

## 5. Experimental account layer excluded

Do not include `DeployAccountLayer.s.sol` in the supported lending deployment. It deploys its own EntryPoint, factory and paymasters, but does not supply a working signer service, bundler, account workflow or verified `handleOps` lifecycle. FXRP recovery after execution is not guaranteed. The script's historical assertion that no canonical v0.9 EntryPoint exists on Coston2 was not verified and must not be used as an infrastructure fact. Experiments require separate local validation and a settlement design review before any public sponsor deposit.

## 6. Connect the frontend

```bash
cd frontend
npm install
cp .env.example .env
```

Edit `.env`:
```
VITE_POOL_ADDRESS=<Pool address from step 3>
VITE_POOL_CHAIN_ID=114
```

```bash
npm run dev
```

The frontend (`src/lib/wagmi.ts`) already has Coston2 configured as a
selectable chain. In your wallet, add Coston2 if it isn't already there:
- **Network name:** Flare Testnet Coston2
- **RPC URL:** https://coston2-api.flare.network/ext/C/rpc
- **Chain ID:** 114
- **Currency symbol:** C2FLR
- **Block explorer:** https://coston2-explorer.flare.network

Fund your wallet from the [Coston2 faucet](https://faucet.flare.network/coston2)
(both C2FLR for gas and testnet FXRP to actually deposit), connect it in
the app, and you should see the FXRP/WFLR reserves populated with real
on-chain data.

## 7. Try a real deposit

Either through the frontend UI, or via `cast` the same way as
`DEPLOY_LOCAL.md` step 6 — substitute `--rpc-url coston2` and the real FXRP
address for the mock one, and use `getReserveId(string)(bytes32) "FXRP"` /
`"WFLR"` (these are the actual names `DeployCoston2.s.sol` registers them
under — no "m" prefix this time, unlike the local mocks).

## 8. Minting FXRP from real XRP (optional)

The faucet shortcut in steps 1/6 covers testing. For the full trust-minimized
mint flow — reserve collateral from an agent, pay real XRP on the XRPL
testnet, get a Flare Data Connector attestation, execute the mint — see
`contracts/scripts/fassets/README.md`. That flow is genuinely how a user would
acquire FXRP outside a testnet faucet (i.e. on mainnet), so it's worth
running through at least once if the demo needs to show it, rather than
relying on the faucet the whole time.

## Troubleshooting

**`insufficient funds for gas`.** Get more C2FLR from the faucet — Coston2
gas is free to obtain but every deploy/transaction still needs some.

**A `forge script` call hangs or times out.** Coston2's public RPC can be
slow under load; retry, or try again after a short wait. `cast chain-id
--rpc-url coston2` is a good quick check that the endpoint is responsive at
all before assuming something's wrong with the script itself.

**Reserve prices look wrong / `FtsoOracle: price stale` reverts.**
`FtsoOracle` is deployed with a 90-second staleness window
(`ORACLE_STALE_PERIOD` in `DeployCoston2.s.sol`). If FTSOv2 feed updates are
lagging on Coston2 for any reason, reads revert rather than silently using
stale data — this is by design (see `src/oracle/FtsoOracle.sol`), not a
bug, but it does mean occasional retries may be needed.


## Appendix: explicit experimental deployment opt-in

The account deployment script aborts before configuration reads or broadcast unless `ENABLE_EXPERIMENTAL_ACCOUNT_LAYER=true`. Both paymaster deposits default to zero. For an isolated experiment, explicitly opt in:

```bash
ENABLE_EXPERIMENTAL_ACCOUNT_LAYER=true \
FTSO_ORACLE=0x... VERIFYING_SIGNER=0x... \
forge script scripts/DeployAccountLayer.s.sol --rpc-url coston2
```

This command simulates and does not broadcast. `EXPERIMENTAL_PAYMASTER_DEPOSIT` is an optional amount in native-token wei deposited into **each** paymaster; leave it unset for zero funding. Opt-in does not resolve the lifecycle or recovery limitations above.
