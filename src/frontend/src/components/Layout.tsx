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
} from "@fluentui/react-icons";
import "./Layout.css";

const NAV = [
  {
    section: "WORKSPACE",
    items: [
      { to: "/",              label: "Dashboard",      icon: <Home24Regular />,         sub: "Overview & status" },
      { to: "/system",        label: "System",         icon: <Settings24Regular />,     sub: "Components, config & agents" },
      { to: "/projects",      label: "Projects",       icon: <Folder24Regular />,       sub: "Manage engagements" },
      { to: "/questionnaire", label: "Questionnaire",  icon: <Clipboard24Regular />,    sub: "Collect baseline data" },
      { to: "/evidence",      label: "Evidence",       icon: <Document24Regular />,     sub: "Upload reports & files" },
    ]
  },
  {
    section: "DISCOVERY",
    items: [
      { to: "/agents",       label: "Agents",        icon: <PlugConnected24Regular />, sub: "Docker assessment agents" },
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
  "/system":            { title: "System",           sub: "Component health, configuration and agent overview" },
  "/projects":          { title: "Projects",         sub: "Manage customers and assessment engagements" },
  "/questionnaire":     { title: "Questionnaire",    sub: "Capture baseline business and technical context" },
  "/evidence":          { title: "Evidence Library",  sub: "Upload and parse assessment report files" },
  "/agents":            { title: "Agents",           sub: "Register, monitor and dispatch assessment agents" },
  "/inventory":         { title: "DB Inventory",     sub: "Discovered database estate" },
  "/environments":      { title: "Environments",     sub: "Manage project environments" },
  "/portfolio":         { title: "Portfolio",        sub: "Group databases for migration planning" },
  "/communication-map": { title: "Communication Map",sub: "Visualise and validate dependency flows" },
  "/reports":           { title: "Reports",          sub: "AI-assisted migration assessment reports" },
  "/ai-settings":       { title: "AI Settings",      sub: "Configure AI Foundry provider and test connection" },
};

export default function Layout() {
  const location = useLocation();
  const meta = PAGE_META[location.pathname] ?? { title: "Assessment Toolkit", sub: "" };

  return (
    <div className="layout">
      <aside className="sidebar">
        <div className="sidebar-brand">
          <div className="brand-logo"><DataBarVertical24Regular /></div>
          <div className="brand-text">
            <span className="brand-name">DB Assess</span>
            <span className="brand-sub">Migration Toolkit</span>
          </div>
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
                >
                  <span className="nav-icon">{item.icon}</span>
                  <span>{item.label}</span>
                </NavLink>
              ))}
            </div>
          ))}
        </nav>

        <div className="sidebar-footer">
          <div className="user-avatar">A</div>
          <div className="user-info">
            <span className="user-name">Admin</span>
            <span className="user-role">Delivery Engineer</span>
          </div>
          <div className="status-dot" title="Online" />
        </div>
      </aside>

      <div className="main-area">
        <header className="topbar">
          <div className="topbar-left">
            <span className="page-title">{meta.title}</span>
            {meta.sub && <span className="page-sub">{meta.sub}</span>}
          </div>
          <div className="topbar-right">
            {meta.badge && (
              <span className="topbar-badge">
                <span style={{ width: 7, height: 7, borderRadius: "50%", background: "#22c55e", display: "inline-block" }} />
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
