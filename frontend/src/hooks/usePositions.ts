import { useQuery } from '@tanstack/react-query'
import { useConfig, useAccount } from 'wagmi'
import { fetchUserPositions } from '../services/poolService'
import { fetchAllReserveData } from '../services/poolService'
import type { PositionInfo, RawPosition, RawReserveData } from '../types'
import { toNumber, computeBorrowRate, RAY } from '../lib/math'

function transformPosition(
  raw: RawPosition,
  index: number,
  reserveMap: Map<`0x${string}`, RawReserveData>,
): PositionInfo {
  const collateralReserve = reserveMap.get(raw.collateralReserveId)
  const borrowReserve = reserveMap.get(raw.borrowReserveId)

  // realDebt = scaledDebt × borrowLiquidityIndex / RAY
  const realDebt = borrowReserve
    ? toNumber((raw.scaledDebt * borrowReserve.borrowLiquidityIndex) / RAY)
    : toNumber(raw.scaledDebt)

  // collateralLocked is static — no transform
  const collateralLocked = toNumber(raw.collateralLocked)

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
    queryKey: ['positions', address],
    enabled: !!address,
    queryFn: async () => {
      const [rawPositions, rawReserves] = await Promise.all([
        fetchUserPositions(config, address!),
        fetchAllReserveData(config),
      ])

      const reserveMap = new Map<`0x${string}`, RawReserveData>()
      rawReserves.forEach((r) => reserveMap.set(r.id, r))

      return rawPositions
        .map((pos, i) => transformPosition(pos, i, reserveMap))
        .filter((p) => p.realDebt > 0) // skip empty/closed positions
    },
    staleTime: 20_000,
  })
}
