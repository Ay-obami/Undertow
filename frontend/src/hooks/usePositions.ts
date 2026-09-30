import { useQuery } from '@tanstack/react-query'
import { useConfig, useAccount } from 'wagmi'
import { fetchUserPositions } from '../services/poolService'
import { fetchAllReserveData } from '../services/poolService'
import type { PositionInfo, RawPosition, RawReserveData } from '../types'
import { bindPositionIds } from '../lib/frontendSafety'
import { POOL_ADDRESS, POOL_CHAIN_ID, POOL_CONFIGURED } from '../lib/wagmi'
import { toNumber, computeBorrowRate, RAY } from '../lib/math'

function transformPosition(
  raw: RawPosition,
  index: number,
  reserveMap: Map<`0x${string}`, RawReserveData>,
  debtAmount: bigint,
): PositionInfo {
  const collateralReserve = reserveMap.get(raw.collateralReserveId)
  const borrowReserve = reserveMap.get(raw.borrowReserveId)

  const realDebt = toNumber(debtAmount, borrowReserve?.decimals)

  // collateralLocked is static — no transform
  const collateralLocked = toNumber(raw.collateralLocked, collateralReserve?.decimals)

  // Borrow APY comes from the reserve, not stored in position
  let borrowAPY = 0
  if (borrowReserve) {
    const utilizationRay =
      borrowReserve.totalDeposits === 0n
        ? 0n
        : (borrowReserve.totalBorrows * RAY) / borrowReserve.totalDeposits

    borrowAPY = computeBorrowRate(
      utilizationRay,
      borrowReserve.baseInterestRate,
      borrowReserve.slope1,
      borrowReserve.slope2,
      borrowReserve.optimalUtilization,
    )
  }

  // Falls back to a shortened reserveId if the reserve wasn't found in the
  // map (shouldn't normally happen — getAllReserves and getUserPositions
  // are fetched together — but better a readable fallback than a crash).
  const collateralAsset = collateralReserve?.reserveName ?? `${raw.collateralReserveId.slice(0, 10)}…`
  const borrowAsset = borrowReserve?.reserveName ?? `${raw.borrowReserveId.slice(0, 10)}…`

  return {
    id: index,
    debtAmount,
    collateralAsset,
    borrowAsset,
    realDebt,
    collateralLocked,
    bufferPercent: Number(raw.bufferPercent) / 1e18,
    borrowAPY,
  }
}

export function usePositions() {
  const config = useConfig()
  const { address } = useAccount()

  return useQuery({
    queryKey: ['positions', POOL_CHAIN_ID, POOL_ADDRESS, address],
    enabled: !!address && POOL_CONFIGURED,
    queryFn: async () => {
      const [rawPositions, rawReserves] = await Promise.all([
        fetchUserPositions(config, address!),
        fetchAllReserveData(config),
      ])

      const reserveMap = new Map<`0x${string}`, RawReserveData>()
      rawReserves.forEach((r) => reserveMap.set(r.id, r))

      return bindPositionIds(rawPositions.positions, rawPositions.ids)
        .map(({ position, id }, index) => transformPosition(position, id, reserveMap, rawPositions.debts[index]))
        .filter((p) => p.realDebt > 0) // skip empty/closed positions
    },
    staleTime: 20_000,
  })
}
