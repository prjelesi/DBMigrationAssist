import { BrowserRouter, Routes, Route, NavLink } from "react-router-dom";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import Dashboard from "./pages/Dashboard";
import NewAssessment from "./pages/NewAssessment";
import Agents from "./pages/Agents";
import CollectJobs from "./pages/CollectJobs";
import Reports from "./pages/Reports";

const queryClient = new QueryClient({
  defaultOptions: { queries: { staleTime: 10_000 } },
});

const NAV = [
  { to: "/", label: "Dashboard" },
  { to: "/new-assessment", label: "New Assessment" },
  { to: "/agents", label: "Agents" },
  { to: "/collect-jobs", label: "Collections" },
  { to: "/reports", label: "Reports" },
];

export default function App() {
  return (
    <QueryClientProvider client={queryClient}>
      <BrowserRouter>
        <div className="min-h-screen flex flex-col">
          {/* Top nav */}
          <nav className="bg-slate-900 text-white">
            <div className="max-w-7xl mx-auto px-6 py-3 flex items-center gap-8">
              <div className="font-bold text-blue-400 tracking-tight text-lg">DBMigrate</div>
              <div className="flex gap-1">
                {NAV.map(n => (
                  <NavLink
                    key={n.to}
                    to={n.to}
                    end={n.to === "/"}
                    className={({ isActive }) =>
                      `px-3 py-1.5 rounded-md text-sm font-medium transition-colors ${isActive ? "bg-blue-600 text-white" : "text-slate-300 hover:text-white hover:bg-slate-700"}`
                    }
                  >
                    {n.label}
                  </NavLink>
                ))}
              </div>
            </div>
          </nav>

          {/* Page content */}
          <main className="flex-1">
            <Routes>
              <Route path="/" element={<Dashboard />} />
              <Route path="/new-assessment" element={<NewAssessment />} />
              <Route path="/agents" element={<Agents />} />
              <Route path="/collect-jobs" element={<CollectJobs />} />
              <Route path="/reports" element={<Reports />} />
            </Routes>
          </main>
        </div>
      </BrowserRouter>
    </QueryClientProvider>
  );
}
