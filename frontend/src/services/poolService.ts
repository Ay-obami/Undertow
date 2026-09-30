/**
 * Contract service layer — ALL contract interactions live here.
 * Updated for the refactored modular pool:
 *   • all reserve lookups use bytes32 IDs (not strings)
 *   • getReserveData → getReserve / getAllReserves
 *   • getUserPositions returns only open positions (no empty slots)
 */

import {
  readContract,
  getAccount,
  getBlockNumber,
  simulateContract,
  writeContract,
  waitForTransactionReceipt,
} from '@wagmi/core'
import type { Config } from 'wagmi'
import { POOL_ABI, ERC20_ABI } from '../lib/abi'
import { POOL_ADDRESS, POOL_CHAIN_ID, POOL_CONFIGURED } from '../lib/wagmi'
import { MAX_REPAY } from '../lib/frontendSafety'
import type { RawReserveData, RawPosition } from '../types'

// ─── Read functions ────────────────────────────────────────────────────────

export async function fetchAllReserveData(config: Config): Promise<RawReserveData[]> {
  requireDeployment()
  const blockNumber = await getBlockNumber(config, { chainId: POOL_CHAIN_ID })
  const data = await readContract(config, {
    blockNumber,
    chainId: POOL_CHAIN_ID,
    address: POOL_ADDRESS,
    abi: POOL_ABI,
    functionName: 'getAllReserves',   // was getAllReserveData
  })
  return Promise.all((data as Omit<RawReserveData, 'decimals'>[]).map(async reserve => ({
    ...reserve,
    decimals: await readContract(config, { blockNumber, chainId: POOL_CHAIN_ID, address: POOL_ADDRESS, abi: POOL_ABI, functionName: 'getReserveTokenDecimals', args: [reserve.id] }),
  })))
}

export async function fetchReserveData(config: Config, reserveId: `0x${string}`): Promise<RawReserveData> {
  requireDeployment()
  const blockNumber = await getBlockNumber(config, { chainId: POOL_CHAIN_ID })
  const data = await readContract(config, {
    blockNumber,
    chainId: POOL_CHAIN_ID,
    address: POOL_ADDRESS,
    abi: POOL_ABI,
    functionName: 'getReserve',       // was getReserveData(string)
    args: [reserveId],                // bytes32 ID instead of string name
  })
  const decimals = await readContract(config, { blockNumber, chainId: POOL_CHAIN_ID, address: POOL_ADDRESS, abi: POOL_ABI, functionName: 'getReserveTokenDecimals', args: [reserveId] })
  return { ...data, decimals } as RawReserveData
}

export async function fetchUserPositions(config: Config, user: `0x${string}`) {
  requireDeployment()
  const blockNumber = await getBlockNumber(config, { chainId: POOL_CHAIN_ID })
  const [positions, ids] = await Promise.all([
    readContract(config, { chainId: POOL_CHAIN_ID, blockNumber, address: POOL_ADDRESS, abi: POOL_ABI, functionName: 'getUserPositions', args: [user] }),
    readContract(config, { chainId: POOL_CHAIN_ID, blockNumber, address: POOL_ADDRESS, abi: POOL_ABI, functionName: 'getUserPositionIds', args: [user] }),
  ])
  const debts = await Promise.all(ids.map(id => readContract(config, { chainId: POOL_CHAIN_ID, blockNumber, address: POOL_ADDRESS, abi: POOL_ABI, functionName: 'getPositionDebt', args: [user, id] })))
  return { positions: [...positions] as RawPosition[], ids: [...ids], debts }

}

function requireDeployment() {
  if (!POOL_CONFIGURED) throw new Error('Configure a pool address and its deployment chain before using the protocol')
}

export async function fetchUserDepositBalance(
  config: Config,
  reserveId: `0x${string}`,         // bytes32 instead of string
  user: `0x${string}`,
): Promise<bigint> {
  requireDeployment()
  const data = await readContract(config, {
    chainId: POOL_CHAIN_ID,
    address: POOL_ADDRESS,
    abi: POOL_ABI,
    functionName: 'getUserDepositBalance',
    args: [reserveId, user],
  })
  return data as bigint
}

export async function fetchTokenBalance(
  config: Config,
  tokenAddress: `0x${string}`,
  user: `0x${string}`,
): Promise<bigint> {
  return readContract(config, {
    chainId: POOL_CHAIN_ID,
    address: tokenAddress,
    abi: ERC20_ABI,
    functionName: 'balanceOf',
    args: [user],
  }) as Promise<bigint>
}

export async function fetchAllowance(
  config: Config,
  tokenAddress: `0x${string}`,
  owner: `0x${string}`,
  spender: `0x${string}`,
): Promise<bigint> {
  return readContract(config, {
    chainId: POOL_CHAIN_ID,
    address: tokenAddress,
    abi: ERC20_ABI,
    functionName: 'allowance',
    args: [owner, spender],
  }) as Promise<bigint>
}

// ─── Write helpers ─────────────────────────────────────────────────────────

async function executeWrite(
  config: Config,
  args: Parameters<typeof simulateContract>[1],
): Promise<`0x${string}`> {
  requireDeployment()
  const account = getAccount(config)
  if (!account.address || account.chainId !== POOL_CHAIN_ID) throw new Error(`Connect your wallet to chain ${POOL_CHAIN_ID}`)
  const { request } = await simulateContract(config, { ...args, chainId: POOL_CHAIN_ID, account: account.address })
  const hash = await writeContract(config, request)
  const receipt = await waitForTransactionReceipt(config, { hash, chainId: POOL_CHAIN_ID })
  if (receipt.status !== 'success') throw new Error('Transaction reverted')
  if (args.functionName === 'repay' && args.args?.[3] === MAX_REPAY) {
    const openIds = await readContract(config, { chainId: POOL_CHAIN_ID, blockNumber: receipt.blockNumber, address: POOL_ADDRESS, abi: POOL_ABI, functionName: 'getUserPositionIds', args: [account.address] })
    if (openIds.includes(args.args[2] as bigint)) throw new Error('Repayment confirmed but position remains open; refresh before retrying')
  }
  return hash
}

export async function approveToken(
  config: Config,
  tokenAddress: `0x${string}`,
  amount: bigint,
): Promise<`0x${string}`> {
  return executeWrite(config, {
    chainId: POOL_CHAIN_ID,
    address: tokenAddress,
    abi: ERC20_ABI,
    functionName: 'approve',
    args: [POOL_ADDRESS, amount],
  })
}

export async function depositToPool(
  config: Config,
  reserveId: `0x${string}`,        // bytes32 ID
  amount: bigint,
): Promise<`0x${string}`> {
  return executeWrite(config, {
    chainId: POOL_CHAIN_ID,
    address: POOL_ADDRESS,
    abi: POOL_ABI,
    functionName: 'deposit',
    args: [reserveId, amount],
  })
}

export async function withdrawFromPool(
  config: Config,
  reserveId: `0x${string}`,        // bytes32 ID
  amount: bigint,
): Promise<`0x${string}`> {
  return executeWrite(config, {
    chainId: POOL_CHAIN_ID,
    address: POOL_ADDRESS,
    abi: POOL_ABI,
    functionName: 'withdraw',
    args: [reserveId, amount],
  })
}

export async function borrowFromPool(
  config: Config,
  collateralId: `0x${string}`,     // bytes32 ID
  borrowId: `0x${string}`,         // bytes32 ID
  amount: bigint,
  bufferPercent: bigint,
): Promise<`0x${string}`> {
  return executeWrite(config, {
    chainId: POOL_CHAIN_ID,
    address: POOL_ADDRESS,
    abi: POOL_ABI,
    functionName: 'borrow',
    args: [collateralId, borrowId, amount, bufferPercent],
  })
}

export async function repayToPool(
  config: Config,
  collateralId: `0x${string}`,     // bytes32 ID
  borrowId: `0x${string}`,         // bytes32 ID
  positionId: bigint,
  repayAmount: bigint,
): Promise<`0x${string}`> {
  return executeWrite(config, {
    chainId: POOL_CHAIN_ID,
    address: POOL_ADDRESS,
    abi: POOL_ABI,
    functionName: 'repay',
    args: [collateralId, borrowId, positionId, repayAmount],
  })
}

export async function liquidatePosition(
  config: Config,
  user: `0x${string}`,
  positionId: bigint,
): Promise<`0x${string}`> {
  return executeWrite(config, {
    chainId: POOL_CHAIN_ID,
    address: POOL_ADDRESS,
    abi: POOL_ABI,
    functionName: 'liquidate',
    args: [user, positionId],
  })
}
