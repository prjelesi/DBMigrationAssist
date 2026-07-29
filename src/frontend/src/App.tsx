import { lazy, Suspense } from "react";
import { BrowserRouter, Route, Routes } from "react-router-dom";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { FluentProvider, webLightTheme } from "@fluentui/react-components";
import Layout from "./components/Layout";

const Dashboard       = lazy(() => import("./pages/Dashboard"));
const Environments    = lazy(() => import("./pages/Environments"));
const Projects        = lazy(() => import("./pages/Projects"));
const Agents          = lazy(() => import("./pages/Agents"));
const Inventory       = lazy(() => import("./pages/Inventory"));
const Portfolio       = lazy(() => import("./pages/Portfolio"));
const CommunicationMap = lazy(() => import("./pages/CommunicationMap"));
const Reports         = lazy(() => import("./pages/Reports"));
const Questionnaire   = lazy(() => import("./pages/Questionnaire"));
const Evidence        = lazy(() => import("./pages/Evidence"));
const AiSettings      = lazy(() => import("./pages/AiSettings"));
const System          = lazy(() => import("./pages/System"));

const qc = new QueryClient({ defaultOptions: { queries: { retry: 1, staleTime: 30_000 } } });

export default function App() {
  return (
    <FluentProvider theme={webLightTheme}>
      <QueryClientProvider client={qc}>
        <BrowserRouter>
          <Suspense fallback={<div className="loading" />}>
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
          </Suspense>
        </BrowserRouter>
      </QueryClientProvider>
    </FluentProvider>
  );
}
