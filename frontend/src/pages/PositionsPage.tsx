import { useState } from 'react'
import { useAccount } from 'wagmi'
import { usePositions } from '../hooks/usePositions'
import { PositionCard, PositionDetailModal, PositionListSkeleton } from '../components/positions/PositionCard'
import { EmptyState } from '../components/common'
import type { PositionInfo } from '../types'
import { formatNumber, formatPercent } from '../lib/math'

export function PositionsPage() {
  const { address, isConnected } = useAccount()
  const { data: positions, isLoading, error } = usePositions()
  const [selectedPosition, setSelectedPosition] = useState<PositionInfo | null>(null)

  // Summary stats
  const totalDebt = positions?.reduce((s, p) => s + p.realDebt, 0) ?? 0
  const totalCollateral = positions?.reduce((s, p) => s + p.collateralLocked, 0) ?? 0

  if (!isConnected) {
    return (
      <div className="flex flex-col items-center justify-center py-24 text-center">
        <div className="w-16 h-16 rounded-full border border-[#2A2A2E] flex items-center justify-center mb-6">
          <svg className="w-7 h-7 text-[#6B7280]" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5">
            <path strokeLinecap="round" strokeLinejoin="round" d="M15.75 5.25a3 3 0 013 3m3 0a6 6 0 01-7.029 5.912c-.563-.097-1.159.026-1.563.43L10.5 17.25H8.25v2.25H6v2.25H2.25v-2.818c0-.597.237-1.17.659-1.591l6.499-6.499c.404-.404.527-1 .43-1.563A6 6 0 1121.75 8.25z" />
          </svg>
        </div>
        <p className="font-display font-bold text-lg text-white mb-2">Connect your wallet</p>
        <p className="text-[#6B7280] text-sm">Connect to view your lending positions</p>
      </div>
    )
  }

  if (error) {
    return <EmptyState message="Failed to load positions" sub="Check your connection and try again" />
  }

  return (
    <div className="space-y-8">
      {/* Summary */}
      {(isLoading || (positions && positions.length > 0)) && (
        <div className="grid grid-cols-2 md:grid-cols-3 gap-4">
          <SummaryCard
            label="Total Positions"
            value={isLoading ? '…' : String(positions?.length ?? 0)}
          />
          <SummaryCard
            label="Total Debt"
            value={isLoading ? '…' : formatNumber(totalDebt)}
          />
          <SummaryCard
            label="Total Collateral"
            value={isLoading ? '…' : formatNumber(totalCollateral)}
          />
        </div>
      )}

      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="font-display font-bold text-xl text-white">My Positions</h1>
          <p className="text-[#6B7280] text-sm mt-0.5">Track and manage your open borrow positions</p>
        </div>
        {positions && positions.length > 0 && (
          <span className="font-mono text-xs text-[#6B7280]">
            {positions.length} open position{positions.length !== 1 ? 's' : ''}
          </span>
        )}
      </div>

      {isLoading ? (
        <PositionListSkeleton />
      ) : !positions?.length ? (
        <EmptyState
          message="No open positions"
          sub="Use the Borrow tab to open your first position"
        />
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          {positions.map((position) => (
            <PositionCard
              key={position.id}
              position={position}
              onClick={() => setSelectedPosition(position)}
            />
          ))}
        </div>
      )}

      <PositionDetailModal
        position={selectedPosition}
        open={!!selectedPosition}
        onClose={() => setSelectedPosition(null)}
      />
    </div>
  )
}

function SummaryCard({ label, value }: { label: string; value: string }) {
  return (
    <div className="card p-4">
      <div className="stat-label mb-1">{label}</div>
      <div className="font-display font-bold text-xl text-white num">{value}</div>
    </div>
  )
}
