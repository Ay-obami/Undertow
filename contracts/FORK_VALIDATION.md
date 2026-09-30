# Fork and local deployment lifecycle validation

The opt-in PinnedForkTest fixes Ethereum block **26,088,938**. It reads actual USDC and WETH metadata (6 and 18 decimals), real USDC/USD and ETH/USD Chainlink feeds, then deploys this repository's Pool, ChainlinkOracle, and VariableInterestStrategy. ERC20 balances are supplied with Foundry deal; no external account is used and no public-chain transaction is broadcast.

The test supplies 10,000 USDC of liquidity and one WETH of collateral, borrows 1,000 USDC, checks an independent USD collateral bound, advances one day, checks accrued debt, repays MAX, and withdraws both lenders' deposits. It asserts zero remaining debt and deposits. The adapter's seven-day stale period deliberately accommodates the pinned feeds and simulated one-day accrual; this is a test configuration, not a deployment recommendation.

Run with an archive-capable RPC:
```sh
LENDING_FORK_RPC_URL=https://ethereum-rpc.publicnode.com forge test --match-contract PinnedForkTest -vv
```
Without LENDING_FORK_RPC_URL the test explicitly skips. RPC failures with a supplied endpoint fail rather than skip.

Initial block 20,000,000 could supply a block header but Publicnode rejected account state with RPC -32603, "state at block #20000001 is pruned". Alternate public endpoints returned HTTP403/405 in this execution environment. A recent fixed block, 26,088,938, was therefore selected and successfully tested. The test does not dynamically follow latest state.

DeployedLifecycleTest deploys local ERC20 tokens with six/eighteen decimals, deterministic feeds, the real oracle adapter, strategy and Pool. It exercises the same economic and settlement assertions. It can run normally or against a local Anvil backend:
```sh
anvil --port 8547
forge test --match-contract DeployedLifecycleTest --fork-url http://127.0.0.1:8547 -vv
```
This smoke deploys contracts inside Foundry's forked test EVM; it is not an RPC-broadcast deployment rehearsal. The Ethereum fork validates actual token/feed interoperability; it does not validate Flare registry availability, FTSO fee mechanics, proxy upgrades, live governance configuration, or production deployment operations.


## RPC-broadcast local rehearsal

With Anvil running and Foundry on PATH, run `python3 ../scripts/rehearse_lending.py` from `contracts/`. The script requires chain 31337 and Anvil's node-info method before broadcasting. It deploys the standard local mocks and pool with an unlocked Anvil account, supplies both reserves, borrows, advances RPC time one day, repays MAX and withdraws all free claims. It asserts zero final debt and deposits. CI runs this separately from the in-test-EVM smoke. Broadcast/cache files are generated locally and are not source artifacts. Never supply a public RPC or funded production signer.
