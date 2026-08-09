import { useAccount } from 'wagmi'
import { BorrowForm } from '../components/borrow/BorrowForm'
import { useReserves } from '../hooks/useReserves'
import { formatPercent, formatNumber } from '../lib/math'

export function BorrowPage() {
  const { isConnected } = useAccount()
  const { data: reserves } = useReserves()

  return (
    <div className="space-y-8">
      {/* Header */}
      <div>
        <h1 className="font-display font-bold text-xl text-white">Borrow</h1>
        <p className="text-[#6B7280] text-sm mt-0.5">
          Lock collateral to borrow assets from the protocol
        </p>
      </div>

      <div className="grid grid-cols-1 xl:grid-cols-5 gap-6">
        {/* Borrow form */}
        <div className="xl:col-span-3">
          {!isConnected ? (
            <div className="panel p-8 flex flex-col items-center text-center">
              <div className="w-12 h-12 rounded-full border border-[#2A2A2E] flex items-center justify-center mb-4">
                <svg className="w-5 h-5 text-[#6B7280]" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5">
                  <path strokeLinecap="round" strokeLinejoin="round" d="M15.75 5.25a3 3 0 013 3m3 0a6 6 0 01-7.029 5.912c-.563-.097-1.159.026-1.563.43L10.5 17.25H8.25v2.25H6v2.25H2.25v-2.818c0-.597.237-1.17.659-1.591l6.499-6.499c.404-.404.527-1 .43-1.563A6 6 0 1121.75 8.25z" />
                </svg>
              </div>
              <p className="text-[#A1A1AA] font-medium mb-1">Connect your wallet</p>
              <p className="text-[#6B7280] text-xs">Connect to start borrowing</p>
            </div>
          ) : (
            <BorrowForm />
          )}
        </div>

        {/* Borrowable markets sidebar */}
        <div className="xl:col-span-2 space-y-4">
          <h2 className="font-semibold text-sm text-[#A1A1AA]">Borrowable Markets</h2>
          {reserves?.borrowable.map((reserve) => (
            <div key={reserve.name} className="card p-4 space-y-3">
              <div className="flex items-center justify-between">
                <div className="flex items-center gap-2">
                  <div className="w-7 h-7 rounded-full bg-[#2A2A2E] flex items-center justify-center text-xs font-mono font-bold text-[#A1A1AA]">
                    {reserve.name.replace('m', '').slice(0, 2)}
                  </div>
                  <span className="font-display font-bold text-sm text-white">{reserve.name}</span>
                </div>
                <span className="font-mono text-sm font-semibold text-[#EAB308]">
                  {formatPercent(reserve.borrowAPY)}
                </span>
              </div>
              <div className="grid grid-cols-2 gap-2 text-xs">
                <div>
                  <span className="text-[#6B7280]">Available: </span>
                  <span className="font-mono text-[#A1A1AA]">
                    {formatNumber(reserve.totalDeposits - reserve.totalBorrows)}
                  </span>
                </div>
                <div>
                  <span className="text-[#6B7280]">Utilization: </span>
                  <span className="font-mono text-[#A1A1AA]">{formatPercent(reserve.utilizationRate)}</span>
                </div>
              </div>
            </div>
          ))}
        </div>
      </div>

      {/* Protocol info */}
      <div className="panel p-5">
        <h3 className="text-sm font-semibold text-[#A1A1AA] mb-4">How Borrowing Works</h3>
        <div className="grid grid-cols-1 md:grid-cols-3 gap-4 text-sm">
          <InfoBlock
            step="01"
            title="Select Collateral"
            desc="Choose an asset you've deposited. It will be locked proportionally to your borrow."
          />
          <InfoBlock
            step="02"
            title="Borrow Assets"
            desc="Pick a borrowable asset and amount. Set a collateral buffer for extra safety margin."
          />
          <InfoBlock
            step="03"
            title="Manage Risk"
            desc="Monitor your health factor. Repay debt to unlock collateral and close your position."
          />
        </div>
      </div>
    </div>
  )
}

function InfoBlock({ step, title, desc }: { step: string; title: string; desc: string }) {
  return (
    <div className="space-y-2">
      <div className="font-mono text-xs text-accent">{step}</div>
      <div className="font-semibold text-white">{title}</div>
      <div className="text-[#6B7280] text-xs leading-relaxed">{desc}</div>
    </div>
  )
}
