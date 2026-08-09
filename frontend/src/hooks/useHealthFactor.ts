import { useReadContract, useReadContracts } from 'wagmi'
import { POOL_ABI } from '../lib/abi'
import { POOL_ADDRESS } from '../lib/wagmi'
import { RAY } from '../lib/math'

/**
 * Numeric health-factor estimate for display, computed client-side from the
 * position + both reserves' currently-stored indices.
 *
 * Note: this mirrors what the on-chain `_checkHealth` did *before* the
 * Week 3 fix (see contracts/AUDIT_WEEK3.md) — it reads each reserve's
 * stored `borrowLiquidityIndex` directly rather than previewing what it
 * would be at the current block. That's an acceptable approximation for a
 * UI display value (worst case it under/overstates HF by whatever interest
 * accrued since the borrow reserve was last touched by anyone), but it must
 * never be used to decide whether to *call* `liquidate()` — the contract's
 * own `checkPositionHealth(user, positionId)` is the authoritative,
 * always-current answer for that, and correctly accounts for pending
 * interest via `ReserveLib.previewBorrowIndex`. If this hook is ever wired
 * into a "liquidate" action rather than just a badge, switch it to read
 * `checkPositionHealth` directly instead of recomputing here.
 */
export function useHealthFactor(
  user: `0x${string}` | undefined,
  positionId: number,
  enabled = false,
) {
  const { data: positions } = useReadContract({
    address: POOL_ADDRESS,
    abi: POOL_ABI,
    functionName: 'getUserPositions',
    args: user ? [user] : undefined,
    query: {
      enabled: !!user && enabled,
      staleTime: 15_000,
    },
  })

  const position = (positions as Array<{
    collateralReserveId: `0x${string}`
    borrowReserveId: `0x${string}`
    scaledDebt: bigint
    collateralLocked: bigint
  }> | undefined)?.[positionId]

  const hasPosition = !!position && position.scaledDebt > 0n

  const { data: reserveResults } = useReadContracts({
    contracts: [
      {
        address: POOL_ADDRESS,
        abi: POOL_ABI,
        functionName: 'getReserve',
        args: position ? [position.collateralReserveId] : ['0x0'],
      },
      {
        address: POOL_ADDRESS,
        abi: POOL_ABI,
        functionName: 'getReserve',
        args: position ? [position.borrowReserveId] : ['0x0'],
      },
    ],
    query: {
      enabled: hasPosition && enabled,
      staleTime: 15_000,
    },
  })

  const collateralReserve = reserveResults?.[0]?.result as
    | { liquidationThreshold: bigint }
    | undefined

  const borrowReserve = reserveResults?.[1]?.result as
    | { borrowLiquidityIndex: bigint }
    | undefined

  const isLoading = enabled && !!user && hasPosition && (!collateralReserve || !borrowReserve)

  let healthFactor: number | undefined

  if (position && collateralReserve && borrowReserve) {
    if (position.scaledDebt === 0n) {
      healthFactor = Infinity
    } else {
      const adjustedCollateral =
        (position.collateralLocked * collateralReserve.liquidationThreshold) / RAY
      const realDebt = (position.scaledDebt * borrowReserve.borrowLiquidityIndex) / RAY
      if (realDebt === 0n) {
        healthFactor = Infinity
      } else {
        const hfRay = (adjustedCollateral * RAY) / realDebt
        healthFactor = Number(hfRay) / 1e18
      }
    }
  }

  return { data: healthFactor, isLoading }
}
