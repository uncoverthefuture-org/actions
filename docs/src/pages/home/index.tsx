/**
 * Home Screen Component
 * 
 * The main layout component that displays the documentation interface.
 * Contains:
 * - Logo with "Docs" branding
 * - Theme toggle (light/dark mode)
 * - Sidebar navigation (in iframe)
 * - Documentation content (in iframe)
 * 
 * URL Routing:
 * - Reads the current URL path to determine which documentation to display
 * - Syncs URL with sidebar navigation clicks
 * - Supports deep linking (e.g., /docs/uncover/actions/ssh-container-deploy)
 */

import React, { useRef, useCallback, useEffect } from "react";
import { useLocation, useNavigate } from "react-router-dom";
import styles from "@pages/home/styles.module.scss";
import LogoDocsCard from "@components/logo_docs_card";
import ThemeToggle from "@components/theme_toggle";
import Window from "@components/window";
import { useTheme } from "@/providers/theme_provider";

/**
 * Converts a URL path to an internal documentation route.
 * 
 * @param pathname - The browser URL pathname (e.g., "/docs/uncover/actions/ssh-container-deploy")
 * @returns The internal route used by the doc content frame (e.g., "/uncover/actions/ssh-container-deploy")
 */
const pathToRoute = (pathname: string): string => {
  // Remove "/docs" prefix if present to get the internal route
  if (pathname.startsWith("/docs")) {
    return pathname.replace("/docs", "") || "/";
  }
  return pathname;
};

/**
 * Converts an internal route to a URL path for the browser.
 * 
 * @param route - The internal route (e.g., "/uncover/actions/ssh-container-deploy")
 * @returns The browser URL path (e.g., "/docs/uncover/actions/ssh-container-deploy")
 */
const routeToPath = (route: string): string => {
  // The root route "/" stays as "/"
  // All other routes get "/docs" prefix
  if (route === "/") {
    return "/";
  }
  return `/docs${route}`;
};

const HomeScreen: React.FC = () => {
  // Reference to the canvas section for potential future drag interactions
  const canvasRef = useRef<HTMLElement | null>(null);

  // React Router hooks for reading and updating the URL
  const location = useLocation();
  const navigate = useNavigate();

  // Theme context for dark/light mode
  const { mode } = useTheme();

  /**
   * Derive the current active route from the browser URL.
   * This is passed to the sidebar and doc content iframes.
   */
  const activeRoute = pathToRoute(location.pathname);

  /**
   * Handle navigation events from the sidebar iframe.
   * 
   * When a user clicks a navigation item in the sidebar:
   * 1. The sidebar sends a postMessage with the route
   * 2. This handler updates the browser URL
   * 3. The new URL triggers a re-render with the new activeRoute
   * 
   * @param data - The message payload from the sidebar iframe
   */
  const handleSidebarOutput = useCallback((data: unknown) => {
    const output = data as { action?: string; route?: string };

    // Only handle "navigate" actions
    if (output.action === "navigate" && output.route) {
      // Convert the internal route to a browser URL path
      const newPath = routeToPath(output.route);

      // Update the browser URL (triggers re-render with new activeRoute)
      navigate(newPath);
    }
  }, [navigate]);

  /**
   * Dynamic styles for the canvas based on theme.
   * In dark mode, we use a darker background with lighter dots.
   */
  const canvasStyle: React.CSSProperties = mode === "dark"
    ? {
      backgroundColor: "#1a1a1a",
      backgroundImage: "radial-gradient(circle, #333 1px, transparent 1px)",
    }
    : {};

  return (
    <section
      ref={canvasRef}
      className={styles.infiniteCanvas}
      style={canvasStyle}
    >
      {/* Header row: Logo and theme toggle */}
      <div className={styles.headerRow}>
        <LogoDocsCard
          logoSrc="/uncoverthefuture.svg"
          logoAlt="uncoverthefuture"
          linkTo="/"
          isDark={mode === "dark"}
        />
        <ThemeToggle />
      </div>

      {/* Main content area: Sidebar and documentation */}
      <div className={styles.windowsContainer}>
        {/* 
          Sidebar Window
          - Fixed width of 280px
          - Receives: activeRoute (for highlighting), theme (for dark mode)
          - Sends: navigation events via onOutput callback
        */}
        <Window
          src="/frames/sidebar"
          input={{
            dimensions: { width: "280px", height: "100%" },
            data: { activeRoute, theme: mode },
            resizable: false,
          }}
          onOutput={handleSidebarOutput}
        />

        {/* 
          Documentation Content Window
          - Fills remaining width
          - Receives: route (for content), theme (for dark mode)
        */}
        <Window
          src="/frames/doc_content"
          input={{
            dimensions: { width: "100%", height: "100%" },
            data: { route: activeRoute, theme: mode },
          }}
        />
      </div>
    </section>
  );
};

export default HomeScreen;
