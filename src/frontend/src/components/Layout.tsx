import { useState } from "react";
import { NavLink, Outlet, useLocation } from "react-router-dom";
import {
  Home24Regular,
  Settings24Regular,
  Folder24Regular,
  Clipboard24Regular,
  Document24Regular,
  PlugConnected24Regular,
  Database24Regular,
  Cloud24Regular,
  AppsList24Regular,
  ArrowShuffle24Regular,
  DocumentText24Regular,
  Bot24Regular,
  DataBarVertical24Regular,
  Dismiss24Regular,
  Navigation24Regular,
  Pulse24Regular,
} from "@fluentui/react-icons";
import { Button, Tooltip } from "@fluentui/react-components";
import "./Layout.css";

const NAV = [
  {
    section: "WORKSPACE",
    items: [
      { to: "/",              label: "Dashboard",      icon: <Home24Regular />,         sub: "Overview & status" },
      { to: "/system",        label: "System",         icon: <Settings24Regular />,     sub: "Components, config & discovery agents" },
      { to: "/projects",      label: "Projects",       icon: <Folder24Regular />,       sub: "Manage engagements" },
      { to: "/questionnaire", label: "Questionnaire",  icon: <Clipboard24Regular />,    sub: "Collect baseline data" },
      { to: "/evidence",      label: "Evidence",       icon: <Document24Regular />,     sub: "Upload reports & files" },
    ]
  },
  {
    section: "DISCOVERY",
    items: [
      { to: "/agents",       label: "Discovery Agents", icon: <PlugConnected24Regular />, sub: "Database discovery workers" },
      { to: "/inventory",    label: "DB Inventory",  icon: <Database24Regular />,      sub: "Database estate" },
      { to: "/environments", label: "Environments",  icon: <Cloud24Regular />,         sub: "Project environments" },
    ]
  },
  {
    section: "PLANNING",
    items: [
      { to: "/portfolio",         label: "Portfolio",  icon: <AppsList24Regular />,      sub: "Migration groups" },
      { to: "/communication-map", label: "Comm. Map",  icon: <ArrowShuffle24Regular />,  sub: "Dependency flows" },
    ]
  },
  {
    section: "REPORTING",
    items: [
      { to: "/reports",     label: "Reports",     icon: <DocumentText24Regular />, sub: "AI-generated assessments" },
      { to: "/ai-settings", label: "AI Settings", icon: <Bot24Regular />,          sub: "Configure AI Foundry" },
    ]
  }
];

const PAGE_META: Record<string, { title: string; sub: string; badge?: string }> = {
  "/":                  { title: "Dashboard",        sub: "Your assessment workspace at a glance", badge: "Live" },
  "/system":            { title: "System",           sub: "Component health, configuration and discovery agent overview" },
  "/projects":          { title: "Projects",         sub: "Manage customers and assessment engagements" },
  "/questionnaire":     { title: "Questionnaire",    sub: "Capture baseline business and technical context" },
  "/evidence":          { title: "Evidence Library",  sub: "Upload and parse assessment report files" },
  "/agents":            { title: "Discovery Agents", sub: "Register, monitor and dispatch database discovery agents" },
  "/inventory":         { title: "DB Inventory",     sub: "Discovered database estate" },
  "/environments":      { title: "Environments",     sub: "Manage project environments" },
  "/portfolio":         { title: "Portfolio",        sub: "Group databases for migration planning" },
  "/communication-map": { title: "Communication Map",sub: "Visualise and validate dependency flows" },
  "/reports":           { title: "Reports",          sub: "AI-assisted migration assessment reports" },
  "/ai-settings":       { title: "AI Settings",      sub: "Configure AI Foundry provider and test connection" },
};

export default function Layout() {
  const location = useLocation();
  const [navigationOpen, setNavigationOpen] = useState(false);
  const meta = PAGE_META[location.pathname] ?? { title: "Assessment Toolkit", sub: "" };

  return (
    <div className="layout">
      {navigationOpen && <button className="nav-scrim" aria-label="Close navigation" onClick={() => setNavigationOpen(false)} />}
      <aside className={`sidebar${navigationOpen ? " open" : ""}`} aria-label="Primary navigation">
        <div className="sidebar-brand">
          <div className="brand-logo"><DataBarVertical24Regular /></div>
          <div className="brand-text">
            <span className="brand-name">DB Migration Assist</span>
            <span className="brand-sub">Assessment workspace</span>
          </div>
          <Tooltip content="Close navigation" relationship="label">
            <Button className="nav-close" appearance="subtle" icon={<Dismiss24Regular />} onClick={() => setNavigationOpen(false)} />
          </Tooltip>
        </div>

        <nav className="sidebar-nav">
          {NAV.map(group => (
            <div key={group.section}>
              <div className="nav-section">
                <span className="nav-section-label">{group.section}</span>
              </div>
              {group.items.map(item => (
                <NavLink
                  key={item.to}
                  to={item.to}
                  end={item.to === "/"}
                  className={({ isActive }) => `nav-item${isActive ? " active" : ""}`}
                  onClick={() => setNavigationOpen(false)}
                >
                  <span className="nav-icon">{item.icon}</span>
                  <span className="nav-copy">
                    <span className="nav-label">{item.label}</span>
                    <span className="nav-description">{item.sub}</span>
                  </span>
                </NavLink>
              ))}
            </div>
          ))}
        </nav>

        <div className="sidebar-footer">
          <div className="workspace-status"><Pulse24Regular /></div>
          <div className="user-info">
            <span className="user-name">Workspace services</span>
            <span className="user-role">Connected</span>
          </div>
          <div className="status-dot" title="Services connected" />
        </div>
      </aside>

      <div className="main-area">
        <header className="topbar">
          <Tooltip content="Open navigation" relationship="label">
            <Button className="nav-open" appearance="subtle" icon={<Navigation24Regular />} onClick={() => setNavigationOpen(true)} />
          </Tooltip>
          <div className="topbar-left">
            <span className="page-title">{meta.title}</span>
            {meta.sub && <span className="page-sub">{meta.sub}</span>}
          </div>
          <div className="topbar-right">
            {meta.badge && (
              <span className="topbar-badge">
                <span className="live-dot" />
                {meta.badge}
              </span>
            )}
          </div>
        </header>

        <main className="content">
          <Outlet />
        </main>
      </div>
    </div>
  );
}
