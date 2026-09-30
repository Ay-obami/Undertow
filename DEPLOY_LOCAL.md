# Deploying locally (Anvil) for testing

This covers deploying the protocol to a local Anvil node and exercising it
end to end — deposit, borrow, repay — before touching a real network. The original author reported running this walkthrough against a fresh Anvil instance. Those historical results are not verification of the current revision; run the commands below and record the current result.

This local path uses **mock tokens and a mock oracle** — no Flare-specific
infrastructure (FTSO, FAssets) is available locally, since those only exist
on real Flare networks. For that, see `DEPLOY_TESTNET.md`.

## 1. Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation) (`forge`, `anvil`, `cast`)
- Node.js 18+ (only needed if you'll also run the frontend)

Confirm Foundry is installed:

```bash
forge --version
anvil --version
```

## 2. Install contract dependencies

From the repo root:

```bash
cd contracts
forge build
```

For a fresh clone, initialize the repository's pinned dependencies from the root:

```bash
git submodule update --init --recursive
cd contracts
forge build
```

Avoid unpinned `forge install` or cloning dependency heads into `lib/`; they change the reviewed dependency set.

`forge build` should finish with `Compiler run successful!` (a handful of
lint notes about naming conventions are expected and harmless).

## 3. Start Anvil

In its own terminal:

```bash
anvil
```

Leave this running. It prints 10 funded test accounts and their private
keys — copy one of each; you'll need both below. This guide uses:

```
Account: 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
Private key: 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
```

(These are Anvil's well-known default account #0 — the same every time you
start a fresh Anvil instance with no extra flags. Fine for local testing;
never use them for anything real.)

## 4. Deploy

In a second terminal, from `contracts/`:

```bash
forge script scripts/Deploy.s.sol \
  --rpc-url http://127.0.0.1:8545 \
  --broadcast \
  --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
```

You should see `ONCHAIN EXECUTION COMPLETE & SUCCESSFUL` and a set of
logged addresses:

```
Pool deployed at:       0x...
Strategy deployed at:   0x...
Oracle deployed at:     0x...
mUSDT deployed at:      0x...
mWETH deployed at:      0x...
mWBTC deployed at:      0x...
```

**Copy these down — they're different every run** (they depend on your
deployer address and nonce). This script also:
- Deploys a `MockOracle` and sets fixed test prices for each asset
- Adds mUSDT/mWETH/mWBTC as reserves via `Pool.addReserve`
- Mints 1,000,000 mUSDT / 1,000 mWETH / 100 mWBTC to the deploying account
- Seeds the pool with half of each as starting liquidity (so there's
  something to borrow against immediately)

## 5. Verify the deployment

Using the `Pool` address from step 4. Note the deploy script registers
reserves as **`mUSDT`, `mWETH`, `mWBTC`** (the "m" prefix, for "mock") —
`getReserveId` is a pure hash function, so passing the wrong name silently
computes an ID for a reserve that was never registered rather than erroring
helpfully:

```bash
POOL=<paste Pool address>

# Confirm a reserve was registered
cast call $POOL "getReserveId(string)(bytes32)" "mUSDT" --rpc-url http://127.0.0.1:8545

# Read it back
cast call $POOL "getReserve(bytes32)" $(cast call $POOL "getReserveId(string)(bytes32)" "mUSDT" --rpc-url http://127.0.0.1:8545) --rpc-url http://127.0.0.1:8545
```

A non-zero `bytes32` from the first command and a populated tuple from the
second confirm the deployment is live and readable.

## 6. Try a full deposit → borrow → repay cycle

Using a second account (Anvil account #1) as a borrower, and the token/pool
addresses from step 4:

```bash
BORROWER_KEY=0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d
BORROWER=0x70997970C51812dc3A010C7d01b50e0d17dc79C8
WETH=<paste mWETH address>
USDT=<paste mUSDT address>

# Give the borrower some WETH (only the deployer holds minted tokens initially)
cast send $WETH "transfer(address,uint256)" $BORROWER 10000000000000000000 \
  --rpc-url http://127.0.0.1:8545 --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

WETH_ID=$(cast call $POOL "getReserveId(string)(bytes32)" "mWETH" --rpc-url http://127.0.0.1:8545)
USDT_ID=$(cast call $POOL "getReserveId(string)(bytes32)" "mUSDT" --rpc-url http://127.0.0.1:8545)

# Borrower deposits 10 WETH as collateral
cast send $WETH "approve(address,uint256)" $POOL 10000000000000000000 \
  --rpc-url http://127.0.0.1:8545 --private-key $BORROWER_KEY

cast send $POOL "deposit(bytes32,uint256)" $WETH_ID 10000000000000000000 \
  --rpc-url http://127.0.0.1:8545 --private-key $BORROWER_KEY

# Borrower borrows 10,000 USDT against it, 5% buffer
cast send $POOL "borrow(bytes32,bytes32,uint256,uint256)" \
  $WETH_ID $USDT_ID 10000000000000000000000 50000000000000000 \
  --rpc-url http://127.0.0.1:8545 --private-key $BORROWER_KEY

# Confirm the position is healthy
cast call $POOL "checkPositionHealth(address,uint256)(bool)" $BORROWER 0 --rpc-url http://127.0.0.1:8545
# → true

# Repay it
cast send $USDT "approve(address,uint256)" $POOL 10000000000000000000000 \
  --rpc-url http://127.0.0.1:8545 --private-key $BORROWER_KEY

cast send $POOL "repay(bytes32,bytes32,uint256,uint256)" \
  $WETH_ID $USDT_ID 0 10000000000000000000000 \
  --rpc-url http://127.0.0.1:8545 --private-key $BORROWER_KEY
```

If every `cast send` above returns `status: 1 (success)`, the full cycle
works end to end.

## 7. Run the automated test suite instead

For most purposes this is faster and more thorough than manual `cast`
commands — the above is for when you specifically want to poke the
contracts by hand (e.g. debugging, or checking frontend integration):

```bash
cd contracts
forge test
```

Use the actual test count and result from your checked-out revision; the historical count of 179 is not a current assertion. For deeper output on the full deposit/
borrow/liquidate lifecycle, see `test/unit/BorrowModule.t.sol`,
`test/unit/LiquidationModule.t.sol`, and `test/unit/BugAudit.t.sol`.

## 8. Connect the frontend to your local deployment

```bash
cd frontend
npm install
cp .env.example .env
```

Edit `.env`:

```
VITE_POOL_ADDRESS=<paste Pool address from step 4>
VITE_POOL_CHAIN_ID=31337
```

```bash
npm run dev
```

In your wallet (MetaMask, etc.), add a network:
- **Network name:** Anvil Local
- **RPC URL:** http://127.0.0.1:8545
- **Chain ID:** 31337
- **Currency symbol:** ETH

Import one of Anvil's test account private keys (step 3) so your wallet has
funds and, if you want to interact with the reserves, some of the minted
mock tokens (use `cast send <token> "transfer(address,uint256)" ...` from
the deployer account to move some to your wallet's address first, the same
way step 6 did for the borrower).

## Troubleshooting

**`Error: error decoding response body` / solc download fails.** `forge
build` needs to download the pinned solc version (`0.8.28`, see
`foundry.toml`) the first time. If you're offline or behind a restrictive
proxy, pre-seed it: download the static Linux binary from
`https://github.com/ethereum/solidity/releases/download/v0.8.28/solc-static-linux`
and place it at `~/.svm/0.8.28/solc-0.8.28` (`chmod +x` it), then re-run
with `forge build --offline`.

**`nonce too low` / `nonce too high` when re-running the deploy script.**
Each `forge script --broadcast` run against the *same* Anvil instance
increments the deployer's nonce, so contract addresses change between runs.
If you restart Anvil (fresh chain state) but reuse an old `broadcast/`
cache, clear it: `rm -rf contracts/broadcast contracts/cache`.

**Frontend shows zero/empty data.** Almost always `VITE_POOL_ADDRESS`
either isn't set or doesn't match your current deployment — re-check
`frontend/.env` against the address `forge script` actually logged, and
set `VITE_POOL_CHAIN_ID=31337` and connect your wallet to Anvil. The example environment defaults to Coston2 (114), so changing only the pool address is insufficient.

**`insufficient funds for gas`.** Only the account that ran `forge script
--broadcast` (the deployer) holds minted mock tokens and pool-seeded
liquidity by default. Every other account — including ones you import into
a wallet — starts with plenty of ETH (Anvil funds all 10 default accounts)
but zero mUSDT/mWETH/mWBTC until you transfer some, as shown in step 6.
