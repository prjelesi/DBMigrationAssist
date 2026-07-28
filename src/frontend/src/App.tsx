import { BrowserRouter, Route, Routes } from "react-router-dom";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import Layout from "./components/Layout";
import Dashboard from "./pages/Dashboard";
import Environments from "./pages/Environments";
import Projects from "./pages/Projects";
import Agents from "./pages/Agents";
import Inventory from "./pages/Inventory";
import Portfolio from "./pages/Portfolio";
import CommunicationMap from "./pages/CommunicationMap";
import Reports from "./pages/Reports";
import Questionnaire from "./pages/Questionnaire";
import Evidence from "./pages/Evidence";
import AiSettings from "./pages/AiSettings";
import System from "./pages/System";

const qc = new QueryClient({ defaultOptions: { queries: { retry: 1, staleTime: 30_000 } } });

export default function App() {
  return (
    <QueryClientProvider client={qc}>
      <BrowserRouter>
        <Routes>
          <Route path="/" element={<Layout />}>
            <Route index element={<Dashboard />} />
            <Route path="system" element={<System />} />
            <Route path="projects" element={<Projects />} />
            <Route path="questionnaire" element={<Questionnaire />} />
            <Route path="evidence" element={<Evidence />} />
            <Route path="agents" element={<Agents />} />
            <Route path="inventory" element={<Inventory />} />
            <Route path="environments" element={<Environments />} />
            <Route path="portfolio" element={<Portfolio />} />
            <Route path="communication-map" element={<CommunicationMap />} />
            <Route path="reports" element={<Reports />} />
            <Route path="ai-settings" element={<AiSettings />} />
          </Route>
        </Routes>
      </BrowserRouter>
    </QueryClientProvider>
  );
}
