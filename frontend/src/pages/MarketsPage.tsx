import { useState } from 'react'
import { useReserves } from '../hooks/useReserves'
import { ReserveCard, ReserveDetailModal, ReserveListSkeleton } from '../components/reserves/ReserveCard'
import { EmptyState } from '../components/common'
import type { ReserveInfo } from '../types'
import { formatNumber, formatPercent } from '../lib/math'

export function MarketsPage() {
  const { data: reserves, isLoading, error } = useReserves()
  const [selectedReserve, setSelectedReserve] = useState<ReserveInfo | null>(null)

  // Protocol-level stats
  const totalTVL = reserves?.all.reduce((s, r) => s + r.totalDeposits, 0) ?? 0
  const totalBorrows = reserves?.all.reduce((s, r) => s + r.totalBorrows, 0) ?? 0

  if (error) {
    return (
      <EmptyState
        message="Failed to load market data"
        sub="Check your RPC connection and try again"
      />
    )
  }

  return (
    <div className="space-y-8">
      {/* Protocol stats banner */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
        <StatBanner label="Total TVL" value={`$${formatNumber(totalTVL)}`} loading={isLoading} />
        <StatBanner label="Total Borrowed" value={`$${formatNumber(totalBorrows)}`} loading={isLoading} />
        <StatBanner label="Markets" value={String(reserves?.all.length ?? 0)} loading={isLoading} />
        <StatBanner
          label="Active Markets"
          value={String(reserves?.active.length ?? 0)}
          loading={isLoading}
        />
      </div>

      {/* Section header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="font-display font-bold text-xl text-white">Markets</h1>
          <p className="text-[#6B7280] text-sm mt-0.5">Deposit assets to earn yield or use as collateral</p>
        </div>
        {reserves && (
          <span className="font-mono text-xs text-[#6B7280]">
            {reserves.all.length} reserve{reserves.all.length !== 1 ? 's' : ''}
          </span>
        )}
      </div>

      {/* Reserve grid */}
      {isLoading ? (
        <ReserveListSkeleton />
      ) : !reserves?.all.length ? (
        <EmptyState message="No reserves found" sub="The protocol has no active markets yet" />
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-4">
          {reserves.all.map((reserve) => (
            <ReserveCard
              key={reserve.name}
              reserve={reserve}
              onClick={() => setSelectedReserve(reserve)}
            />
          ))}
        </div>
      )}

      {/* Detail modal */}
      <ReserveDetailModal
        reserve={selectedReserve}
        open={!!selectedReserve}
        onClose={() => setSelectedReserve(null)}
      />
    </div>
  )
}

function StatBanner({ label, value, loading }: { label: string; value: string; loading?: boolean }) {
  return (
    <div className="card p-4">
      <div className="stat-label mb-1">{label}</div>
      {loading ? (
        <div className="h-7 w-20 skeleton rounded mt-1" />
      ) : (
        <div className="font-display font-bold text-xl text-white num">{value}</div>
      )}
    </div>
  )
}
