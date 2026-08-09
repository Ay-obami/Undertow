# Deploying to Flare Testnet Coston2

This covers deploying the protocol to Flare's Coston2 testnet, with FXRP and
WFLR as reserves priced via FTSOv2, plus the optional ERC-4337 account layer
for gasless deposit/repay.

**A note on verification:** unlike `DEPLOY_LOCAL.md`, the steps below
haven't been run live against Coston2 from this environment — the sandbox
this was written in has no network access to Flare's RPC endpoints. What
you get instead is careful code review of exactly what each script does
(argument order, registry lookups, access control), the same level of
scrutiny that already caught and fixed a real bug in these scripts (see
`README.md`'s "Bug fixes from original" — the deploy scripts were capturing
the wrong deployer address before a fix). Treat this as a correct,
diligently-reviewed guide rather than a "we ran this and it worked" one, and
if anything doesn't match reality, that's worth reporting back.

## 1. Prerequisites

- Foundry (`forge`, `cast`) — see `DEPLOY_LOCAL.md` step 1
- A wallet with a private key you control (**not** one of Anvil's public
  test keys — this is a real, if low-value, testnet)
- Testnet C2FLR from the [Coston2 faucet](https://faucet.flare.network/coston2)
  — you'll need this for gas on every deploy/transaction below, plus extra
  if you fund the paymasters in step 5
- (Optional, for trying deposits) Testnet FXRP — also available directly
  from the [Coston2 faucet](https://faucet.flare.network/coston2), no
  minting required. For the full mint-from-real-XRP flow instead, see
  `scripts/fassets/README.md`.

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
   address via `ContractRegistry.getWNat()` — no hardcoded addresses, so it
   stays correct even if Flare's deployed addresses change
3. Registers FTSOv2 feed IDs: FXRP → `XRP/USD` (FXRP is 1:1 backed by XRP),
   WFLR → `FLR/USD`
4. Deploys `Pool` and adds FXRP and WFLR as reserves (80%/65% LTV
   respectively — see the script for full risk params)

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
frontend and `FtsoOracle` for step 5.

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

## 5. (Optional) Deploy the account layer for gasless transactions

Only needed if you want deposit/repay to be sponsorable gaslessly (with the
option to bill gas back in FXRP). Skip this if you just want the core
lending pool.

```bash
FTSO_ORACLE=<FtsoOracle address from step 3> \
VERIFYING_SIGNER=<address of the key that will approve gasless UserOps — defaults to your deployer if unset> \
  forge script scripts/DeployAccountLayer.s.sol \
  --rpc-url coston2 \
  --broadcast \
  --private-key 0xYOUR_PRIVATE_KEY
```

Read the `VERIFYING_SIGNER` note in the script before deploying for
anything beyond a demo: it defaults to your deployer key if unset, which is
fine to try this out, but in a real setup your backend's signing key
(the one that decides which UserOps get sponsored) should be a *different*
key than whatever deployed the contracts.

This deploys:
- A fresh `EntryPoint` (Coston2 has no canonical pre-deployed one for this
  account-abstraction version — v0.9 is recent)
- A `SimpleAccountFactory`
- `VerifyingPaymaster` (sponsors gas for pre-approved operations)
- `FxrpGasPaymaster` (same, but bills the gas back in FXRP afterward)
- Funds both paymasters with a starting 0.05 C2FLR EntryPoint deposit each
  (0.1 C2FLR total, on top of the deployment gas itself — make sure your
  key has enough)

**Both paymasters use OpenZeppelin's `Ownable2Step`.** Note the address
that ends up as owner (your deployer, correctly — see the fix noted at the
top of this doc) and keep its key safe: losing it means permanently losing
the ability to call `setVerifyingSigner`, `withdrawTo`, etc. on these
contracts.

## 6. Connect the frontend

```bash
cd frontend
npm install
cp .env.example .env
```

Edit `.env`:
```
VITE_POOL_ADDRESS=<Pool address from step 3>
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
`scripts/fassets/README.md`. That flow is genuinely how a user would
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

**Paymaster `setVerifyingSigner` reverts with no reason / can't call
owner-only functions.** Confirm you're calling from the actual deployer
address from step 5, not a different key — `Ownable2Step` means there's no
recovery if you've lost track of which key owns it.
