/**
 * Root Navigation Configuration
 * 
 * This file defines all routes for the Uncover Docs application.
 * 
 * Route Structure:
 * - "/" and "/docs/*" - Main documentation pages (HomeScreen)
 * - "/frames/*" - Internal iframe routes (not directly navigable by users)
 * 
 * The wildcard route "/docs/*" allows deep linking to specific documentation
 * pages like "/docs/uncover/actions/ssh-container-deploy".
 */

import { Route, Routes, BrowserRouter as Router } from "react-router-dom";
import HomeScreen from "@pages/home/index";
import SidebarFrame from "@pages/frames/sidebar";
import DocContentFrame from "@pages/frames/doc_content";

/**
 * RootNavigator Component
 * 
 * Sets up the React Router with all application routes.
 * Uses BrowserRouter for clean URLs without hash fragments.
 */
const RootNavigator: React.FC = () => {
  return (
    <Router basename="/actions">
      <Routes>
        {/* 
          Main documentation layout route.
          Matches root "/" and any "/docs/*" path.
          The HomeScreen component reads the URL to determine which doc to display.
        */}
        <Route path="/" element={<HomeScreen />} />
        <Route path="/docs/*" element={<HomeScreen />} />

        {/* 
          Internal iframe routes.
          These are loaded inside iframes and receive data via postMessage.
          They should not be navigated to directly by users.
        */}
        <Route path="/frames/sidebar" element={<SidebarFrame />} />
        <Route path="/frames/doc_content" element={<DocContentFrame />} />
      </Routes>
    </Router>
  );
};

export default RootNavigator;
