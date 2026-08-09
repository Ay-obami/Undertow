import { useState } from 'react'
import { Toaster } from 'sonner'
import { Header, PageLayout } from './components/layout/Header'
import { MarketsPage } from './pages/MarketsPage'
import { PositionsPage } from './pages/PositionsPage'
import { BorrowPage } from './pages/BorrowPage'

type Tab = 'markets' | 'positions' | 'borrow'

export default function App() {
  const [activeTab, setActiveTab] = useState<Tab>('markets')

  return (
    <div className="min-h-screen bg-[#0B0B0C] grid-bg relative">
      {/* Subtle radial gradient accent */}
      <div
        className="fixed top-0 left-1/2 -translate-x-1/2 w-[600px] h-[300px] pointer-events-none"
        style={{
          background: 'radial-gradient(ellipse at top, rgba(59,130,246,0.06) 0%, transparent 70%)',
        }}
      />

      <Header activeTab={activeTab} onTabChange={setActiveTab} />

      <PageLayout>
        {activeTab === 'markets' && <MarketsPage />}
        {activeTab === 'positions' && <PositionsPage />}
        {activeTab === 'borrow' && <BorrowPage />}
      </PageLayout>

      <Toaster
        theme="dark"
        position="bottom-right"
        toastOptions={{
          style: {
            background: '#18181B',
            border: '1px solid #2A2A2E',
            color: '#ffffff',
            fontFamily: 'DM Sans, system-ui, sans-serif',
          },
        }}
      />
    </div>
  )
}
