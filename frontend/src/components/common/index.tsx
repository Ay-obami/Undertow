import type { RiskLevel } from '../../types'
import { formatHealthFactor, getRiskLevel } from '../../lib/math'

// ─── Skeleton loader ───────────────────────────────────────────────────────
export function Skeleton({ className = '' }: { className?: string }) {
  return <div className={`skeleton ${className}`} />
}

export function SkeletonText({ lines = 3 }: { lines?: number }) {
  return (
    <div className="space-y-2">
      {Array.from({ length: lines }).map((_, i) => (
        <Skeleton key={i} className={`h-3 rounded ${i === lines - 1 ? 'w-3/4' : 'w-full'}`} />
      ))}
    </div>
  )
}

// ─── Risk dot indicator ────────────────────────────────────────────────────
export function RiskDot({ level }: { level: RiskLevel }) {
  return (
    <span
      className={`inline-block w-2 h-2 rounded-full risk-dot-${level}`}
      aria-label={level}
    />
  )
}

export function RiskBadge({ healthFactor }: { healthFactor: number }) {
  const level = getRiskLevel(healthFactor)
  const label = level === 'healthy' ? 'Healthy' : level === 'warning' ? 'At Risk' : 'Danger'
  const colors = {
    healthy: 'bg-[#22C55E]/10 text-[#22C55E] border-[#22C55E]/20',
    warning: 'bg-[#EAB308]/10 text-[#EAB308] border-[#EAB308]/20',
    danger: 'bg-[#EF4444]/10 text-[#EF4444] border-[#EF4444]/20',
  }
  return (
    <span className={`tag ${colors[level]}`}>
      <span className={`inline-block w-1.5 h-1.5 rounded-full risk-dot-${level} mr-1.5`} />
      {label}
    </span>
  )
}

// ─── Health factor display ─────────────────────────────────────────────────
export function HealthFactorDisplay({
  healthFactor,
  loading,
}: {
  healthFactor?: number
  loading?: boolean
}) {
  if (loading) return <Skeleton className="h-5 w-16 rounded" />
  if (healthFactor === undefined) return <span className="text-[#6B7280] text-sm">—</span>

  const level = getRiskLevel(healthFactor)
  const colorClass = `risk-${level}`

  return (
    <span className={`font-mono font-semibold ${colorClass}`}>
      {formatHealthFactor(healthFactor)}
    </span>
  )
}

// ─── Status badge ──────────────────────────────────────────────────────────
export function StatusBadge({ active }: { active: boolean }) {
  return active ? (
    <span className="tag-active">Active</span>
  ) : (
    <span className="tag-inactive">Inactive</span>
  )
}

// ─── Transaction status bar ───────────────────────────────────────────────
import type { TransactionState } from '../../types'

export function TxStatusBar({ state }: { state: TransactionState }) {
  if (state.status === 'idle') return null

  const colors = {
    simulating: 'border-accent/30 text-[#A1A1AA] bg-accent/5',
    pending: 'border-accent/30 text-[#A1A1AA] bg-accent/5',
    confirming: 'border-accent/30 text-accent bg-accent/5',
    success: 'border-[#22C55E]/30 text-[#22C55E] bg-[#22C55E]/5',
    error: 'border-[#EF4444]/30 text-[#EF4444] bg-[#EF4444]/5',
  }

  const icons = {
    simulating: <SpinnerIcon />,
    pending: <SpinnerIcon />,
    confirming: <SpinnerIcon />,
    success: '✓',
    error: '✕',
  }

  return (
    <div className={`flex items-center gap-2 px-3 py-2.5 rounded-lg border text-sm ${colors[state.status]}`}>
      <span className="shrink-0">{icons[state.status]}</span>
      <span>{state.message}</span>
    </div>
  )
}

function SpinnerIcon() {
  return (
    <svg className="animate-spin w-3.5 h-3.5" viewBox="0 0 24 24" fill="none">
      <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" />
      <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z" />
    </svg>
  )
}

// ─── Empty state ───────────────────────────────────────────────────────────
export function EmptyState({ message, sub }: { message: string; sub?: string }) {
  return (
    <div className="flex flex-col items-center justify-center py-16 text-center">
      <div className="w-12 h-12 rounded-full border border-[#2A2A2E] flex items-center justify-center mb-4">
        <svg className="w-5 h-5 text-[#6B7280]" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5">
          <path strokeLinecap="round" strokeLinejoin="round" d="M9.879 7.519c1.171-1.025 3.071-1.025 4.242 0 1.172 1.025 1.172 2.687 0 3.712-.203.179-.43.326-.67.442-.745.361-1.45.999-1.45 1.827v.75M21 12a9 9 0 11-18 0 9 9 0 0118 0zm-9 5.25h.008v.008H12v-.008z" />
        </svg>
      </div>
      <p className="text-[#A1A1AA] font-medium">{message}</p>
      {sub && <p className="text-[#6B7280] text-xs mt-1">{sub}</p>}
    </div>
  )
}

// ─── Modal backdrop ────────────────────────────────────────────────────────
export function Modal({
  open,
  onClose,
  title,
  children,
}: {
  open: boolean
  onClose: () => void
  title: string
  children: React.ReactNode
}) {
  if (!open) return null
  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4">
      {/* Backdrop */}
      <div
        className="absolute inset-0 bg-black/60 backdrop-blur-sm"
        onClick={onClose}
      />
      {/* Panel */}
      <div className="relative w-full max-w-lg panel p-6 shadow-2xl">
        <div className="flex items-center justify-between mb-6">
          <h2 className="font-display font-bold text-lg text-white">{title}</h2>
          <button
            onClick={onClose}
            className="w-8 h-8 flex items-center justify-center rounded-lg hover:bg-[#2A2A2E] text-[#6B7280] hover:text-white transition-colors"
          >
            ✕
          </button>
        </div>
        {children}
      </div>
    </div>
  )
}

// ─── Utilization bar ───────────────────────────────────────────────────────
export function UtilizationBar({ value }: { value: number }) {
  const pct = Math.min(value * 100, 100)
  const color = value >= 0.9 ? '#EF4444' : value >= 0.75 ? '#EAB308' : '#3B82F6'
  return (
    <div className="w-full h-1 bg-[#2A2A2E] rounded-full overflow-hidden">
      <div
        className="h-full rounded-full transition-all duration-500"
        style={{ width: `${pct}%`, background: color }}
      />
    </div>
  )
}
