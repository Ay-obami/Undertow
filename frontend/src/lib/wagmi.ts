import { http, createConfig } from 'wagmi'
import { defineChain } from 'viem'
import { foundry } from 'viem/chains'
import { injected } from '@wagmi/connectors'

/**
 * Flare Testnet Coston2 — matches contracts/foundry.toml's `coston2` RPC
 * endpoint and scripts/DeployCoston2.s.sol's target network.
 */
export const coston2 = defineChain({
  id: 114,
  name: 'Flare Testnet Coston2',
  nativeCurrency: { name: 'Coston2 Flare', symbol: 'C2FLR', decimals: 18 },
  rpcUrls: {
    default: { http: ['https://coston2-api.flare.network/ext/C/rpc'] },
  },
  blockExplorers: {
    default: { name: 'Coston2 Explorer', url: 'https://coston2-explorer.flare.network' },
  },
  testnet: true,
})

/**
 * Set after running `forge script scripts/DeployCoston2.s.sol --broadcast`
 * (see contracts/README.md) — copy the "Pool deployed at:" address it logs.
 * Falls back to the zero address so the app still builds/runs without a
 * deployment (reads will simply return empty/zero until this is set).
 */
export const POOL_ADDRESS = (import.meta.env.VITE_POOL_ADDRESS ??
  '0x0000000000000000000000000000000000000000') as `0x${string}`

// `foundry` (from viem/chains) is anvil's default: chain id 31337,
// http://127.0.0.1:8545. Both chains are always registered so a wallet can
// switch between "local anvil" and "Coston2" without a rebuild — which
// network you're actually pointed at is just whichever one your wallet has
// selected, plus VITE_POOL_ADDRESS matching a deployment on that chain.
// See DEPLOY_LOCAL.md / DEPLOY_TESTNET.md.
export const wagmiConfig = createConfig({
  chains: [coston2, foundry],
  connectors: [injected()],
  transports: {
    [coston2.id]: http(),
    [foundry.id]: http(),
  },
})
