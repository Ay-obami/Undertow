import { http, createConfig } from 'wagmi'
import { defineChain } from 'viem'
import { foundry } from 'viem/chains'
import { injected } from '@wagmi/connectors'
import { deploymentReady } from './frontendSafety'

export const coston2 = defineChain({
  id: 114,
  name: 'Flare Testnet Coston2',
  nativeCurrency: { name: 'Coston2 Flare', symbol: 'C2FLR', decimals: 18 },
  rpcUrls: { default: { http: ['https://coston2-api.flare.network/ext/C/rpc'] } },
  blockExplorers: { default: { name: 'Coston2 Explorer', url: 'https://coston2-explorer.flare.network' } },
  testnet: true,
})

const address = import.meta.env.VITE_POOL_ADDRESS ?? ''
const chainId = Number(import.meta.env.VITE_POOL_CHAIN_ID)
export const POOL_CONFIGURED = deploymentReady(address, chainId) && [114, 31337].includes(chainId)
export const POOL_CHAIN_ID: 114 | 31337 = chainId === 31337 ? 31337 : 114
export const POOL_ADDRESS = (POOL_CONFIGURED ? address : '0x0000000000000000000000000000000000000000') as `0x${string}`
export const wagmiConfig = createConfig({
  chains: [coston2, foundry],
  connectors: [injected()],
  transports: { [coston2.id]: http(), [foundry.id]: http() },
})
