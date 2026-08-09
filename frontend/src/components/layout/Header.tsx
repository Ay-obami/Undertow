import { useAccount, useConnect, useDisconnect } from 'wagmi'
import { shortenAddress } from '../../lib/math'

export function Header({
  activeTab,
  onTabChange,
}: {
  activeTab: 'markets' | 'positions' | 'borrow'
  onTabChange: (tab: 'markets' | 'positions' | 'borrow') => void
}) {
  const { address, isConnected } = useAccount()
  const { connect, connectors } = useConnect()
  const { disconnect } = useDisconnect()

  const tabs: Array<{ id: 'markets' | 'positions' | 'borrow'; label: string }> = [
    { id: 'markets', label: 'Markets' },
    { id: 'positions', label: 'Positions' },
    { id: 'borrow', label: 'Borrow' },
  ]

  return (
    <header className="sticky top-0 z-30 border-b border-[#2A2A2E] bg-[#0B0B0C]/90 backdrop-blur-sm">
      <div className="max-w-7xl mx-auto px-6 h-16 flex items-center justify-between gap-6">
        {/* Logo */}
        <div className="flex items-center gap-3 shrink-0">
          <div className="w-7 h-7 rounded-lg bg-accent/20 border border-accent/30 flex items-center justify-center">
            <svg className="w-4 h-4 text-accent" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
              <path strokeLinecap="round" strokeLinejoin="round" d="M12 6v6m0 0v6m0-6h6m-6 0H6" />
            </svg>
          </div>
          <span className="font-display font-bold text-base text-white tracking-tight">Pool</span>
          <span className="tag bg-accent/10 text-accent border-accent/20 hidden sm:inline">Protocol</span>
        </div>

        {/* Nav tabs */}
        <nav className="flex gap-1 bg-[#111113] border border-[#2A2A2E] rounded-xl p-1">
          {tabs.map((tab) => (
            <button
              key={tab.id}
              onClick={() => onTabChange(tab.id)}
              className={`px-4 py-1.5 rounded-lg text-sm font-medium transition-all duration-150 ${
                activeTab === tab.id
                  ? 'bg-[#18181B] text-white shadow-sm'
                  : 'text-[#6B7280] hover:text-[#A1A1AA]'
              }`}
            >
              {tab.label}
            </button>
          ))}
        </nav>

        {/* Wallet */}
        <div className="shrink-0">
          {isConnected && address ? (
            <div className="flex items-center gap-2">
              <div className="hidden sm:flex items-center gap-2 bg-[#111113] border border-[#2A2A2E] rounded-lg px-3 py-1.5">
                <span className="w-2 h-2 rounded-full bg-[#22C55E]" />
                <span className="font-mono text-xs text-[#A1A1AA]">{shortenAddress(address)}</span>
              </div>
              <button
                onClick={() => disconnect()}
                className="text-xs text-[#6B7280] hover:text-[#A1A1AA] px-2 py-1.5 rounded-lg hover:bg-[#18181B] transition-colors"
              >
                Disconnect
              </button>
            </div>
          ) : (
            <button
              onClick={() => connect({ connector: connectors[0] })}
              className="btn-primary text-sm"
            >
              Connect Wallet
            </button>
          )}
        </div>
      </div>
    </header>
  )
}

export function PageLayout({ children }: { children: React.ReactNode }) {
  return (
    <div className="max-w-7xl mx-auto px-6 py-8">
      {children}
    </div>
  )
}
