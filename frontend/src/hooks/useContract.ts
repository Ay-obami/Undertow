import { repaymentApprovalAmount } from '../lib/frontendSafety'
import { useState, useCallback } from 'react'
import { useConfig } from 'wagmi'
import { useQueryClient } from '@tanstack/react-query'
import { toast } from 'sonner'
import {
  approveToken,
  depositToPool,
  withdrawFromPool,
  borrowFromPool,
  repayToPool,
  liquidatePosition,
  fetchAllowance,
  fetchTokenBalance,
} from '../services/poolService'
import { POOL_ADDRESS } from '../lib/wagmi'
import { decodeContractError } from '../lib/math'
import { computeReserveId } from '../lib/reserveId'
import type { TransactionState } from '../types'

export function useContract() {
  const config = useConfig()
  const queryClient = useQueryClient()
  const [txState, setTxState] = useState<TransactionState>({ status: 'idle' })

  const invalidateCache = useCallback(() => {
    queryClient.invalidateQueries({ queryKey: ['reserves'] })
    queryClient.invalidateQueries({ queryKey: ['positions'] })
    queryClient.invalidateQueries({ queryKey: ['tokenBalance'] })
    queryClient.invalidateQueries({ queryKey: ['readContract'] })
  }, [queryClient])

  const withTx = useCallback(
    async (label: string, fn: () => Promise<`0x${string}`>) => {
      setTxState({ status: 'simulating', message: `Simulating ${label}…` })
      try {
        const hash = await fn()
        setTxState({ status: 'success', txHash: hash, message: `${label} confirmed!` })
        toast.success(`${label} successful`, { description: `tx: ${hash.slice(0, 10)}…` })
        invalidateCache()
        return hash
      } catch (err) {
        const msg = decodeContractError(err)
        setTxState({ status: 'error', message: msg })
        toast.error(msg)
        throw err
      }
    },
    [invalidateCache],
  )

  const ensureAllowance = useCallback(
    async (
      tokenAddress: `0x${string}`,
      owner: `0x${string}`,
      amount: bigint,
    ) => {
      const current = await fetchAllowance(config, tokenAddress, owner, POOL_ADDRESS)
      if (current >= amount) return
      setTxState({ status: 'pending', message: 'Approving token…' })
      try {
        await approveToken(config, tokenAddress, amount)
        toast.success('Token approved')
      } catch (err) {
        const msg = decodeContractError(err)
        setTxState({ status: 'error', message: msg })
        toast.error(msg)
        throw err
      }
    },
    [config],
  )

  const deposit = useCallback(
    async (
      reserveName: string,
      amount: bigint,
      tokenAddress: `0x${string}`,
      owner: `0x${string}`,
    ) => {
      await ensureAllowance(tokenAddress, owner, amount)
      const reserveId = computeReserveId(reserveName)
      return withTx('Deposit', () => depositToPool(config, reserveId, amount))
    },
    [config, ensureAllowance, withTx],
  )

  const withdraw = useCallback(
    async (reserveName: string, amount: bigint) => {
      const reserveId = computeReserveId(reserveName)
      return withTx('Withdrawal', () => withdrawFromPool(config, reserveId, amount))
    },
    [config, withTx],
  )

  const borrow = useCallback(
    async (
      collateralName: string,
      borrowName: string,
      amount: bigint,
      bufferPercent: bigint,
    ) => {
      const collateralId = computeReserveId(collateralName)
      const borrowId = computeReserveId(borrowName)
      return withTx('Borrow', () =>
        borrowFromPool(config, collateralId, borrowId, amount, bufferPercent),
      )
    },
    [config, withTx],
  )

  const repay = useCallback(
    async (
      collateralName: string,
      borrowName: string,
      positionId: number,
      repayAmount: bigint,
      tokenAddress: `0x${string}`,
      owner: `0x${string}`,
    ) => {
      const walletBalance = await fetchTokenBalance(config, tokenAddress, owner)
      const approvalAmount = repaymentApprovalAmount(repayAmount, walletBalance)
      await ensureAllowance(tokenAddress, owner, approvalAmount)
      const collateralId = computeReserveId(collateralName)
      const borrowId = computeReserveId(borrowName)
      return withTx('Repay', () =>
        repayToPool(config, collateralId, borrowId, BigInt(positionId), repayAmount),
      )
    },
    [config, ensureAllowance, withTx],
  )

  const liquidate = useCallback(
    async (
      user: `0x${string}`,
      positionId: number,
      debtTokenAddress: `0x${string}`,
      debtAmount: bigint,
      caller: `0x${string}`,
    ) => {
      await ensureAllowance(debtTokenAddress, caller, debtAmount)
      return withTx('Liquidation', () =>
        liquidatePosition(config, user, BigInt(positionId)),
      )
    },
    [config, ensureAllowance, withTx],
  )

  const resetTxState = useCallback(() => {
    setTxState({ status: 'idle' })
  }, [])

  return { txState, resetTxState, deposit, withdraw, borrow, repay, liquidate }
}
