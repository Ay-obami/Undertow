import { BaseError, ContractFunctionRevertedError } from 'viem'
import type { RiskLevel } from '../types'

// ─── RAY fixed-point math (mirrors src/libraries/MathLib.sol exactly) ──────

export const RAY = 1_000_000_000_000_000_000n // 1e18

/** rounded half-up, matching `MathLib.rayMul` */
export function rayMul(a: bigint, b: bigint): bigint {
  if (a === 0n || b === 0n) return 0n
  return (a * b + RAY / 2n) / RAY
}

/** rounded half-up, matching `MathLib.rayDiv` */
export function rayDiv(a: bigint, b: bigint): bigint {
  if (b === 0n) throw new Error('rayDiv: division by zero')
  return (a * RAY + b / 2n) / b
}

/** Token-unit bigint (assumes 18 decimals) → plain JS number, for display. */
export function toNumber(value: bigint, decimals = 18): number {
  return Number(value) / 10 ** decimals
}

// ─── Interest rate model (mirrors src/modules/VariableInterestStrategy.sol) ─
//
//   borrow rate:
//     util <= optimal  →  baseRate + (util / optimal) * slope1
//     util >  optimal  →  baseRate + slope1 + ((util - optimal) / (1 - optimal)) * slope2
//
//   supply rate:
//     borrowRate * util * (1 - reserveFactor)
//
// Inputs are RAY-scaled bigints exactly as the contract computes them;
// outputs are plain numbers in 0–1 range (e.g. 0.05 = 5% APY) for direct use
// in `formatPercent`. This lets the UI show live rate estimates without a
// round-trip read for every keystroke — `useReserves` already has the
// authoritative on-chain rate for the current state; this is for
// re-deriving it from raw reserve fields already in hand (see
// hooks/useReserves.ts, hooks/usePositions.ts).

export function computeBorrowRate(
  utilizationRay: bigint,
  baseRate: bigint,
  slope1: bigint,
  slope2: bigint,
  optimalUtilization: bigint,
): number {
  let rateRay: bigint
  if (optimalUtilization === 0n) {
    // matches the contract's normal-zone branch collapsing when optimal=0
    rateRay = baseRate
  } else if (utilizationRay <= optimalUtilization) {
    rateRay = baseRate + rayMul(rayDiv(utilizationRay, optimalUtilization), slope1)
  } else {
    const excessUtilization = utilizationRay - optimalUtilization
    const maxExcess = RAY - optimalUtilization
    rateRay = baseRate + slope1 + rayMul(rayDiv(excessUtilization, maxExcess), slope2)
  }
  return Number(rateRay) / 1e18
}

export function computeSupplyRate(
  utilizationRay: bigint,
  baseRate: bigint,
  slope1: bigint,
  slope2: bigint,
  optimalUtilization: bigint,
  reserveFactor: bigint,
): number {
  const borrowRate = computeBorrowRate(utilizationRay, baseRate, slope1, slope2, optimalUtilization)
  const borrowRateRay = BigInt(Math.round(borrowRate * 1e18))
  const afterFactor = RAY - reserveFactor
  const supplyRateRay = rayMul(rayMul(borrowRateRay, utilizationRay), afterFactor)
  return Number(supplyRateRay) / 1e18
}

// ─── Formatting ─────────────────────────────────────────────────────────────

export function formatNumber(value: number, decimals = 2): string {
  if (!Number.isFinite(value)) return '—'
  return value.toLocaleString(undefined, {
    minimumFractionDigits: 0,
    maximumFractionDigits: decimals,
  })
}

/** `value` is a 0–1 ratio (e.g. 0.0523 → "5.23%"). */
export function formatPercent(value: number): string {
  if (!Number.isFinite(value)) return '—'
  return `${(value * 100).toFixed(2)}%`
}

export function formatHealthFactor(healthFactor: number): string {
  if (healthFactor === Infinity) return '∞'
  if (!Number.isFinite(healthFactor)) return '—'
  return healthFactor.toFixed(2)
}

export function getRiskLevel(healthFactor: number): RiskLevel {
  if (healthFactor >= 1.5) return 'healthy'
  if (healthFactor >= 1.05) return 'warning'
  return 'danger'
}

export function shortenAddress(address: string): string {
  if (address.length <= 10) return address
  return `${address.slice(0, 6)}…${address.slice(-4)}`
}

// ─── Error decoding ─────────────────────────────────────────────────────────

/**
 * Turns a viem/wagmi contract error into a short, user-facing message.
 * Prefers the on-chain revert reason (our contracts revert with plain
 * `require` strings, e.g. "Pool: exceeds LTV") over viem's generic wrapper text.
 */
export function decodeContractError(err: unknown): string {
  if (err instanceof BaseError) {
    const revertError = err.walk((e) => e instanceof ContractFunctionRevertedError)
    if (revertError instanceof ContractFunctionRevertedError) {
      const reason = revertError.reason ?? revertError.data?.errorName
      if (reason) return reason
    }
    // Fall back to viem's own short summary rather than the full multi-line error.
    return err.shortMessage ?? err.message
  }
  if (err instanceof Error) return err.message
  return 'Something went wrong. Please try again.'
}
