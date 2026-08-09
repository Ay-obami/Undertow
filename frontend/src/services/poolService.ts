/**
 * Contract service layer — ALL contract interactions live here.
 * Updated for the refactored modular pool:
 *   • all reserve lookups use bytes32 IDs (not strings)
 *   • getReserveData → getReserve / getAllReserves
 *   • getUserPositions returns only open positions (no empty slots)
 */

import {
  readContract,
  simulateContract,
  writeContract,
  waitForTransactionReceipt,
} from '@wagmi/core'
import type { Config } from 'wagmi'
import { POOL_ABI, ERC20_ABI } from '../lib/abi'
import { POOL_ADDRESS } from '../lib/wagmi'
import type { RawReserveData, RawPosition } from '../types'

// ─── Read functions ────────────────────────────────────────────────────────

export async function fetchAllReserveData(config: Config): Promise<RawReserveData[]> {
  const data = await readContract(config, {
    address: POOL_ADDRESS,
    abi: POOL_ABI,
    functionName: 'getAllReserves',   // was getAllReserveData
  })
  return data as RawReserveData[]
}

export async function fetchReserveData(config: Config, reserveId: `0x${string}`): Promise<RawReserveData> {
  const data = await readContract(config, {
    address: POOL_ADDRESS,
    abi: POOL_ABI,
    functionName: 'getReserve',       // was getReserveData(string)
    args: [reserveId],                // bytes32 ID instead of string name
  })
  return data as RawReserveData
}

export async function fetchUserPositions(config: Config, user: `0x${string}`): Promise<RawPosition[]> {
  const data = await readContract(config, {
    address: POOL_ADDRESS,
    abi: POOL_ABI,
    functionName: 'getUserPositions',
    args: [user],
  })
  // All returned positions are open — the contract now filters closed ones
  return data as RawPosition[]
}

export async function fetchUserDepositBalance(
  config: Config,
  reserveId: `0x${string}`,         // bytes32 instead of string
  user: `0x${string}`,
): Promise<bigint> {
  const data = await readContract(config, {
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
  const { request } = await simulateContract(config, args)
  const hash = await writeContract(config, request)
  await waitForTransactionReceipt(config, { hash })
  return hash
}

export async function approveToken(
  config: Config,
  tokenAddress: `0x${string}`,
  amount: bigint,
): Promise<`0x${string}`> {
  return executeWrite(config, {
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
    address: POOL_ADDRESS,
    abi: POOL_ABI,
    functionName: 'liquidate',
    args: [user, positionId],
  })
}
