// ─── On-chain raw structs (bigint from contract) ───────────────────────────
// Field sets and names mirror contracts/src/libraries/DataTypes.sol exactly
// (field ORDER matters for ABI struct decoding — see lib/abi.ts).

export interface RawReserveData {
  decimals: number // hydrated through getReserveTokenDecimals
  id: `0x${string}`
  reserveName: string
  tokenAddress: `0x${string}`
  priceFeed: `0x${string}`
  interestStrategy: `0x${string}`
  liquidationThreshold: bigint
  ltv: bigint
  slope1: bigint
  slope2: bigint
  baseInterestRate: bigint
  optimalUtilization: bigint
  liquidationBonus: bigint
  reserveFactor: bigint
  borrowCap: bigint
  supplyCap: bigint
  totalDeposits: bigint
  totalBorrows: bigint
  supplyLiquidityIndex: bigint
  borrowLiquidityIndex: bigint
  lastUpdateTimestamp: bigint
  isActive: boolean
  isBorrowable: boolean
}

/**
 * Matches DataTypes.Position exactly — reserves are identified by bytes32 ID
 * on-chain, NOT by name. Display names are resolved client-side (see
 * hooks/usePositions.ts) against a reserveId → reserve map built from
 * getAllReserves(); there is no on-chain lookup that returns names directly.
 */
export interface RawPosition {
  collateralReserveId: `0x${string}`
  borrowReserveId: `0x${string}`
  collateralPriceFeed: `0x${string}`
  borrowPriceFeed: `0x${string}`
  scaledDebt: bigint
  collateralLocked: bigint
  bufferPercent: bigint
  isOpen: boolean
}

// ─── Human-readable UI models ──────────────────────────────────────────────

export interface ReserveInfo {
  decimals: number
  name: string
  tokenAddress: `0x${string}`
  priceFeed: `0x${string}`
  totalDeposits: number       // real value, human-readable
  totalBorrows: number        // real value, human-readable
  utilizationRate: number     // 0–1
  supplyAPY: number           // 0–1 (e.g. 0.05 = 5%)
  borrowAPY: number           // 0–1
  liquidationThreshold: number
  ltv: number
  liquidationBonus: number
  reserveFactor: number
  borrowCap: number
  supplyCap: number
  optimalUtilization: number
  isActive: boolean
  isBorrowable: boolean
}

export interface PositionInfo {
  debtAmount: bigint
  id: number
  collateralAsset: string     // resolved display name (falls back to a
  borrowAsset: string         // shortened reserveId if the reserve wasn't found)
  realDebt: number            // scaledDebt × borrowLiquidityIndex / RAY
  collateralLocked: number    // static, no transform
  bufferPercent: number
  borrowAPY: number           // populated from the matching reserve
}

export type RiskLevel = 'healthy' | 'warning' | 'danger'

export interface TransactionState {
  status: 'idle' | 'simulating' | 'pending' | 'confirming' | 'success' | 'error'
  message?: string
  txHash?: `0x${string}`
}
