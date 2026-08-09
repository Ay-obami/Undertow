import { useQuery } from '@tanstack/react-query'
import { useConfig } from 'wagmi'
import { fetchAllReserveData } from '../services/poolService'
import type { ReserveInfo, RawReserveData } from '../types'
import {
  toNumber,
  computeBorrowRate,
  computeSupplyRate,
  RAY,
} from '../lib/math'

function transformReserve(raw: RawReserveData): ReserveInfo {
  const totalDeposits = toNumber(raw.totalDeposits)
  const totalBorrows = toNumber(raw.totalBorrows)
  const utilizationRate = raw.totalDeposits === 0n
    ? 0
    : Number((raw.totalBorrows * RAY) / raw.totalDeposits) / 1e18

  const utilizationRay = raw.totalDeposits === 0n
    ? 0n
    : (raw.totalBorrows * RAY) / raw.totalDeposits

  const borrowAPY = computeBorrowRate(
    utilizationRay,
    raw.baseInterestRate,
    raw.slope1,
    raw.slope2,
    raw.optimalUtilization,
  )

  const supplyAPY = computeSupplyRate(
    utilizationRay,
    raw.baseInterestRate,
    raw.slope1,
    raw.slope2,
    raw.optimalUtilization,
    raw.reserveFactor,
  )

  return {
    name: raw.reserveName,
    tokenAddress: raw.tokenAddress,
    priceFeed: raw.priceFeed,
    totalDeposits,
    totalBorrows,
    utilizationRate,
    supplyAPY,
    borrowAPY,
    liquidationThreshold: Number(raw.liquidationThreshold) / 1e18,
    ltv: Number(raw.ltv) / 1e18,
    liquidationBonus: Number(raw.liquidationBonus) / 1e18,
    reserveFactor: Number(raw.reserveFactor) / 1e18,
    borrowCap: toNumber(raw.borrowCap),
    supplyCap: toNumber(raw.supplyCap),
    optimalUtilization: Number(raw.optimalUtilization) / 1e18,
    isActive: raw.isActive,
    isBorrowable: raw.isBorrowable,
  }
}

export function useReserves() {
  const config = useConfig()

  const query = useQuery({
    queryKey: ['reserves'],
    queryFn: () => fetchAllReserveData(config),
    staleTime: 30_000,
    select: (data) => {
      const all = data.map(transformReserve)
      return {
        all,
        active: all.filter((r) => r.isActive),
        borrowable: all.filter((r) => r.isActive && r.isBorrowable),
        collateral: all.filter((r) => r.isActive),
      }
    },
  })

  return query
}

export function useReserve(reserveName: string | null) {
  const { data } = useReserves()
  if (!reserveName || !data) return null
  return data.all.find((r) => r.name === reserveName) ?? null
}
