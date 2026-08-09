import { useState } from 'react'
import type { ReserveInfo } from '../../types'
import {
  Skeleton,
  StatusBadge,
  UtilizationBar,
  Modal,
} from '../common'
import { formatNumber, formatPercent } from '../../lib/math'
import { DepositWithdrawForm } from '../borrow/DepositWithdrawForm'

// ─── Reserve Card ──────────────────────────────────────────────────────────
export function ReserveCard({
  reserve,
  onClick,
}: {
  reserve: ReserveInfo
  onClick: () => void
}) {
  return (
    <button
      onClick={onClick}
      className="card p-5 text-left w-full hover:border-[#3A3A3E] hover:bg-[#1C1C1F] transition-all duration-200 group"
    >
      <div className="flex items-start justify-between mb-4">
        <div className="flex items-center gap-3">
          {/* Token icon placeholder */}
          <div className="w-9 h-9 rounded-full bg-[#2A2A2E] flex items-center justify-center text-xs font-mono font-bold text-[#A1A1AA]">
            {reserve.name.replace('m', '').slice(0, 2)}
          </div>
          <div>
            <div className="font-display font-bold text-white text-sm">{reserve.name}</div>
            <div className="flex items-center gap-1.5 mt-0.5">
              <StatusBadge active={reserve.isActive} />
              {reserve.isBorrowable && (
                <span className="tag bg-accent/10 text-accent border-accent/20">Borrowable</span>
              )}
            </div>
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

      {/* Stats row */}
      <div className="grid grid-cols-3 gap-3 mb-4">
        <div>
          <div className="stat-label">Total Deposits</div>
          <div className="font-mono font-semibold text-white text-sm mt-0.5">
            {formatNumber(reserve.totalDeposits)}
          </div>
        </div>
        <div>
          <div className="stat-label">Total Borrows</div>
          <div className="font-mono font-semibold text-white text-sm mt-0.5">
            {formatNumber(reserve.totalBorrows)}
          </div>
        </div>
        <div>
          <div className="stat-label">Utilization</div>
          <div className="font-mono font-semibold text-white text-sm mt-0.5">
            {formatPercent(reserve.utilizationRate)}
          </div>
        </div>
      </div>

      <UtilizationBar value={reserve.utilizationRate} />

      {/* APY row */}
      <div className="grid grid-cols-2 gap-3 mt-4">
        <div className="bg-[#0B0B0C] rounded-lg p-2.5">
          <div className="stat-label">Supply APY</div>
          <div className="font-mono font-bold text-[#22C55E] text-sm mt-0.5">
            {formatPercent(reserve.supplyAPY)}
          </div>
        </div>
        <div className="bg-[#0B0B0C] rounded-lg p-2.5">
          <div className="stat-label">Borrow APY</div>
          <div className="font-mono font-bold text-[#EAB308] text-sm mt-0.5">
            {formatPercent(reserve.borrowAPY)}
          </div>
        </div>
      </div>
    </button>
  )
}

// ─── Reserve Detail Modal ──────────────────────────────────────────────────
export function ReserveDetailModal({
  reserve,
  open,
  onClose,
}: {
  reserve: ReserveInfo | null
  open: boolean
  onClose: () => void
}) {
  const [tab, setTab] = useState<'deposit' | 'withdraw'>('deposit')

  if (!reserve) return null

  return (
    <Modal open={open} onClose={onClose} title={reserve.name}>
      <div className="space-y-5">
        {/* Key metrics */}
        <div className="grid grid-cols-2 gap-3">
          <MetricRow label="Supply APY" value={formatPercent(reserve.supplyAPY)} highlight="green" />
          <MetricRow label="Borrow APY" value={formatPercent(reserve.borrowAPY)} highlight="yellow" />
          <MetricRow label="Utilization" value={formatPercent(reserve.utilizationRate)} />
          <MetricRow label="LTV" value={formatPercent(reserve.ltv)} />
          <MetricRow label="Liq. Threshold" value={formatPercent(reserve.liquidationThreshold)} />
          <MetricRow label="Reserve Factor" value={formatPercent(reserve.reserveFactor)} />
        </div>

        <div className="divider" />

        <div className="grid grid-cols-2 gap-3 text-sm">
          <div>
            <div className="stat-label mb-1">Total Deposits</div>
            <div className="font-mono text-white">{formatNumber(reserve.totalDeposits)}</div>
          </div>
          <div>
            <div className="stat-label mb-1">Supply Cap</div>
            <div className="font-mono text-white">{formatNumber(reserve.supplyCap)}</div>
          </div>
          <div>
            <div className="stat-label mb-1">Total Borrows</div>
            <div className="font-mono text-white">{formatNumber(reserve.totalBorrows)}</div>
          </div>
          <div>
            <div className="stat-label mb-1">Borrow Cap</div>
            <div className="font-mono text-white">{formatNumber(reserve.borrowCap)}</div>
          </div>
        </div>

        <div className="divider" />

        {/* Deposit / Withdraw tabs */}
        <div>
          <div className="flex gap-1 bg-[#0B0B0C] rounded-lg p-1 mb-4">
            <button
              onClick={() => setTab('deposit')}
              className={`flex-1 py-2 rounded-md text-sm font-medium transition-all ${
                tab === 'deposit' ? 'bg-[#18181B] text-white' : 'text-[#6B7280] hover:text-[#A1A1AA]'
              }`}
            >
              Deposit
            </button>
            <button
              onClick={() => setTab('withdraw')}
              className={`flex-1 py-2 rounded-md text-sm font-medium transition-all ${
                tab === 'withdraw' ? 'bg-[#18181B] text-white' : 'text-[#6B7280] hover:text-[#A1A1AA]'
              }`}
            >
              Withdraw
            </button>
          </div>

          <DepositWithdrawForm reserve={reserve} mode={tab} onSuccess={onClose} />
        </div>
      </div>
    </Modal>
  )
}

function MetricRow({
  label,
  value,
  highlight,
}: {
  label: string
  value: string
  highlight?: 'green' | 'yellow'
}) {
  const colorClass = highlight === 'green'
    ? 'text-[#22C55E]'
    : highlight === 'yellow'
    ? 'text-[#EAB308]'
    : 'text-white'

  return (
    <div className="bg-[#0B0B0C] rounded-lg p-2.5">
      <div className="stat-label mb-0.5">{label}</div>
      <div className={`font-mono font-semibold text-sm ${colorClass}`}>{value}</div>
    </div>
  )
}

// ─── Reserve list skeleton ─────────────────────────────────────────────────
export function ReserveListSkeleton() {
  return (
    <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-4">
      {[1, 2, 3].map((i) => (
        <div key={i} className="card p-5 space-y-4">
          <div className="flex items-center gap-3">
            <Skeleton className="w-9 h-9 rounded-full" />
            <div className="space-y-2 flex-1">
              <Skeleton className="h-3.5 w-20 rounded" />
              <Skeleton className="h-2.5 w-14 rounded" />
            </div>
          </div>
          <div className="grid grid-cols-3 gap-3">
            {[1, 2, 3].map((j) => (
              <div key={j} className="space-y-1.5">
                <Skeleton className="h-2 w-full rounded" />
                <Skeleton className="h-3 w-3/4 rounded" />
              </div>
            ))}
          </div>
          <Skeleton className="h-1 w-full rounded" />
          <div className="grid grid-cols-2 gap-3">
            <Skeleton className="h-12 rounded-lg" />
            <Skeleton className="h-12 rounded-lg" />
          </div>
        </div>
      ))}
    </div>
  )
}
