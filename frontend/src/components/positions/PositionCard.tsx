import { useState, useEffect } from 'react'
import type { PositionInfo } from '../../types'
import {
  Skeleton,
  RiskBadge,
  HealthFactorDisplay,
  Modal,
  TxStatusBar,
} from '../common'
import { formatNumber, formatPercent, getRiskLevel } from '../../lib/math'
import { useHealthFactor } from '../../hooks/useHealthFactor'
import { useAccount } from 'wagmi'
import { useContract } from '../../hooks/useContract'
import { useReserves } from '../../hooks/useReserves'
import { parseUnits } from 'viem'

// ─── Position Card ─────────────────────────────────────────────────────────
export function PositionCard({
  position,
  onClick,
}: {
  position: PositionInfo
  onClick: () => void
}) {
  const { address } = useAccount()
  const [loadHF, setLoadHF] = useState(false)
  const { data: hf, isLoading: hfLoading } = useHealthFactor(address, position.id, loadHF)

  // Trigger HF load when card mounts (lazy)
  useEffect(() => {
    const timer = setTimeout(() => setLoadHF(true), 300 + position.id * 200)
    return () => clearTimeout(timer)
  }, [position.id])

  const level = hf !== undefined ? getRiskLevel(hf) : 'healthy'

  return (
    <button
      onClick={onClick}
      className={`card p-5 text-left w-full transition-all duration-200 group hover:border-[#3A3A3E] hover:bg-[#1C1C1F]
        ${level === 'danger' ? 'border-[#EF4444]/20' : level === 'warning' ? 'border-[#EAB308]/20' : ''}`}
    >
      {/* Header */}
      <div className="flex items-start justify-between mb-4">
        <div>
          <div className="flex items-center gap-2 mb-1">
            <span className="font-mono text-xs text-[#6B7280]">Position #{position.id}</span>
            {hf !== undefined && <RiskBadge healthFactor={hf} />}
          </div>
          <div className="flex items-center gap-2">
            <span className="font-display font-bold text-white">{position.collateralAsset}</span>
            <svg className="w-3.5 h-3.5 text-[#6B7280]" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
              <path strokeLinecap="round" strokeLinejoin="round" d="M13.5 4.5L21 12m0 0l-7.5 7.5M21 12H3" />
            </svg>
            <span className="font-display font-bold text-white">{position.borrowAsset}</span>
          </div>
        </div>
        <svg
          className="w-4 h-4 text-[#6B7280] group-hover:text-[#A1A1AA] transition-colors mt-1"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          strokeWidth="1.5"
        >
          <path strokeLinecap="round" strokeLinejoin="round" d="M13.5 4.5L21 12m0 0l-7.5 7.5M21 12H3" />
        </svg>
      </div>

      {/* Metrics grid */}
      <div className="grid grid-cols-2 gap-3">
        <div className="bg-[#0B0B0C] rounded-lg p-2.5">
          <div className="stat-label mb-0.5">Real Debt</div>
          <div className="font-mono font-semibold text-white text-sm">
            {formatNumber(position.realDebt)} <span className="text-[#6B7280] text-xs">{position.borrowAsset}</span>
          </div>
        </div>
        <div className="bg-[#0B0B0C] rounded-lg p-2.5">
          <div className="stat-label mb-0.5">Collateral Locked</div>
          <div className="font-mono font-semibold text-white text-sm">
            {formatNumber(position.collateralLocked)} <span className="text-[#6B7280] text-xs">{position.collateralAsset}</span>
          </div>
        </div>
        <div className="bg-[#0B0B0C] rounded-lg p-2.5">
          <div className="stat-label mb-0.5">Borrow APY</div>
          <div className="font-mono font-semibold text-[#EAB308] text-sm">
            {formatPercent(position.borrowAPY)}
          </div>
        </div>
        <div className="bg-[#0B0B0C] rounded-lg p-2.5">
          <div className="stat-label mb-0.5">Health Factor</div>
          <HealthFactorDisplay healthFactor={hf} loading={hfLoading} />
        </div>
      </div>
    </button>
  )
}

// ─── Position Detail Modal ─────────────────────────────────────────────────
export function PositionDetailModal({
  position,
  open,
  onClose,
}: {
  position: PositionInfo | null
  open: boolean
  onClose: () => void
}) {
  const { address } = useAccount()
  const { data: hf, isLoading: hfLoading } = useHealthFactor(address, position?.id ?? 0, open && !!position)
  const { data: reserves } = useReserves()
  const { repay, txState, resetTxState } = useContract()

  const [repayAmount, setRepayAmount] = useState('')
  const [isRepaying, setIsRepaying] = useState(false)

  if (!position) return null

  const borrowReserve = reserves?.all.find((r) => r.name === position.borrowAsset)

  const handleRepay = async () => {
    if (!address || !borrowReserve || !repayAmount) return
    setIsRepaying(true)
    resetTxState()
    try {
      const amount = parseUnits(repayAmount, 18)
      await repay(
        position.collateralAsset,
        position.borrowAsset,
        position.id,
        amount,
        borrowReserve.tokenAddress,
        address,
      )
      setRepayAmount('')
      onClose()
    } catch {
      // error handled in hook
    } finally {
      setIsRepaying(false)
    }
  }

  const setMaxRepay = () => setRepayAmount(position.realDebt.toFixed(6))

  return (
    <Modal open={open} onClose={onClose} title={`Position #${position.id} Detail`}>
      <div className="space-y-5">
        {/* Position overview */}
        <div className="grid grid-cols-2 gap-3">
          <div className="bg-[#0B0B0C] rounded-lg p-3">
            <div className="stat-label mb-1">Collateral</div>
            <div className="font-display font-bold text-white">{position.collateralAsset}</div>
          </div>
          <div className="bg-[#0B0B0C] rounded-lg p-3">
            <div className="stat-label mb-1">Borrow Asset</div>
            <div className="font-display font-bold text-white">{position.borrowAsset}</div>
          </div>
          <div className="bg-[#0B0B0C] rounded-lg p-3">
            <div className="stat-label mb-1">Current Debt</div>
            <div className="font-mono font-semibold text-white">
              {formatNumber(position.realDebt, 4)}
            </div>
          </div>
          <div className="bg-[#0B0B0C] rounded-lg p-3">
            <div className="stat-label mb-1">Collateral Locked</div>
            <div className="font-mono font-semibold text-white">
              {formatNumber(position.collateralLocked, 4)}
            </div>
          </div>
          <div className="bg-[#0B0B0C] rounded-lg p-3">
            <div className="stat-label mb-1">Current Borrow APY</div>
            <div className="font-mono font-semibold text-[#EAB308]">
              {formatPercent(position.borrowAPY)}
            </div>
          </div>
          <div className="bg-[#0B0B0C] rounded-lg p-3">
            <div className="stat-label mb-1">Health Factor</div>
            <HealthFactorDisplay healthFactor={hf} loading={hfLoading} />
          </div>
        </div>

        <div className="divider" />

        {/* Repay section */}
        <div>
          <h3 className="text-sm font-semibold text-[#A1A1AA] mb-3">Repay Debt</h3>
          <div className="space-y-3">
            <div className="relative">
              <input
                type="number"
                value={repayAmount}
                onChange={(e) => setRepayAmount(e.target.value)}
                placeholder="0.0"
                className="input-field pr-16"
                min="0"
                step="any"
              />
              <button
                onClick={setMaxRepay}
                className="absolute right-2 top-1/2 -translate-y-1/2 text-xs text-accent hover:text-blue-400 font-medium px-2 py-1 rounded"
              >
                MAX
              </button>
            </div>
            <div className="text-xs text-[#6B7280]">
              Full debt: <span className="font-mono text-[#A1A1AA]">{formatNumber(position.realDebt, 4)} {position.borrowAsset}</span>
            </div>
            {txState.status !== 'idle' && <TxStatusBar state={txState} />}
            <button
              onClick={handleRepay}
              disabled={!repayAmount || Number(repayAmount) <= 0 || isRepaying}
              className="btn-primary w-full"
            >
              {isRepaying ? 'Processing…' : 'Repay'}
            </button>
          </div>
        </div>
      </div>
    </Modal>
  )
}

// ─── Position list skeleton ────────────────────────────────────────────────
export function PositionListSkeleton() {
  return (
    <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
      {[1, 2].map((i) => (
        <div key={i} className="card p-5 space-y-4">
          <div className="space-y-2">
            <Skeleton className="h-3 w-24 rounded" />
            <Skeleton className="h-4 w-32 rounded" />
          </div>
          <div className="grid grid-cols-2 gap-3">
            {[1, 2, 3, 4].map((j) => (
              <Skeleton key={j} className="h-14 rounded-lg" />
            ))}
          </div>
        </div>
      ))}
    </div>
  )
}
