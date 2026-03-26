/**
 * Sidebar Navigation Frame Component
 * 
 * Provides navigation for the documentation.
 * Sends "navigate" events to the parent window.
 * 
 * Updates:
 * - Auto-expand active route
 * - Mouse movement tracking for parent glow effect
 * - Correct URL format /uncover-actions/
 */

import React, { useState, useEffect, useCallback } from "react";
import styles from "@pages/frames/sidebar/styles.module.scss";

interface SidebarInput {
    activeRoute?: string;
    theme?: "light" | "dark";
}

interface NavItem {
    label: string;
    route?: string;
    children?: NavItem[];
}

// Navigation structure
const navItems: NavItem[] = [
    {
        label: "Home",
        route: "/"
    },
    {
        label: "Introduction",
        route: "/uncover-actions/introduction"
    },
    {
        label: "Packages",
        children: [
            {
                label: "@uncover/actions",
                children: [
                    {
                        label: "Container Deployments",
                        route: "/uncover-actions/container-deployments",
                    },
                    {
                        label: "SSH Container Deploy",
                        route: "/uncover-actions/ssh-container-deploy",
                    },
                ],
            },
        ],
    },
];

// Helper: Find parent labels for auto-expand
const findParentLabels = (
    items: NavItem[],
    targetRoute: string,
    parents: string[] = []
): string[] | null => {
    for (const item of items) {
        if (item.route === targetRoute) {
            return parents;
        }
        if (item.children) {
            const found = findParentLabels(
                item.children,
                targetRoute,
                [...parents, item.label]
            );
            if (found) return found;
        }
    }
    return null;
};

const SidebarFrame: React.FC = () => {
    const [activeRoute, setActiveRoute] = useState<string>("/");
    const [expandedItems, setExpandedItems] = useState<Set<string>>(new Set());
    const [theme, setTheme] = useState<"light" | "dark">("light");

    const sendOutput = useCallback((action: string, data?: Record<string, unknown>) => {
        window.parent.postMessage(
            { type: "WINDOW_OUTPUT", payload: { action, ...(data || {}) } },
            "*"
        );
    }, []);

    // Mouse tracking for parent glow effect
    useEffect(() => {
        let ticking = false;
        const onMouseMove = (e: MouseEvent) => {
            if (!ticking) {
                window.requestAnimationFrame(() => {
                    sendOutput("mousemove", { x: e.clientX, y: e.clientY });
                    ticking = false;
                });
                ticking = true;
            }
        };
        window.addEventListener("mousemove", onMouseMove);
        return () => window.removeEventListener("mousemove", onMouseMove);
    }, [sendOutput]);

    // Listen for inputs
    useEffect(() => {
        const handleMessage = (event: MessageEvent) => {
            if (event.data?.type === "WINDOW_INPUT") {
                const input = event.data.payload?.data as SidebarInput | undefined;
                if (input?.activeRoute) {
                    setActiveRoute(input.activeRoute);
                    const parents = findParentLabels(navItems, input.activeRoute);
                    if (parents && parents.length > 0) {
                        setExpandedItems(new Set(parents));
                    }
                }
                if (input?.theme) {
                    setTheme(input.theme);
                }
            }
        };

        window.addEventListener("message", handleMessage);
        return () => window.removeEventListener("message", handleMessage);
    }, []);

    const handleNavClick = useCallback(
        (item: NavItem) => {
            if (item.children) {
                setExpandedItems((prev) => {
                    const next = new Set(prev);
                    if (next.has(item.label)) {
                        next.delete(item.label);
                    } else {
                        next.add(item.label);
                    }
                    return next;
                });
            } else if (item.route) {
                sendOutput("navigate", { route: item.route });
            }
        },
        [sendOutput]
    );

    const getDepthIndicator = (depth: number): React.ReactNode => {
        if (depth === 0) return null;
        return <span className={styles.depth_indicator}>{"›".repeat(depth)}</span>;
    };

    const renderNavItem = (item: NavItem, depth = 0) => {
        const isExpanded = expandedItems.has(item.label);
        const isActive = item.route === activeRoute;
        const hasChildren = item.children && item.children.length > 0;

        return (
            <div key={item.label} className={styles.nav_item_wrapper}>
                <div
                    className={`${styles.nav_item} ${isActive ? styles.active : ""}`}
                    onClick={() => handleNavClick(item)}
                >
                    {getDepthIndicator(depth)}
                    {hasChildren && (
                        <span className={`${styles.chevron} ${isExpanded ? styles.expanded : ""}`}>
                            ▶
                        </span>
                    )}
                    <span className={styles.label}>{item.label}</span>
                </div>
                {hasChildren && isExpanded && (
                    <div className={styles.children}>
                        {item.children!.map((child) => renderNavItem(child, depth + 1))}
                    </div>
                )}
            </div>
        );
    };

    const isDark = theme === "dark";

    return (
        <div className={`${styles.sidebar} ${isDark ? styles.dark : ""}`}>
            <div className={styles.header}>
                <span className={styles.title}>Navigation</span>
            </div>
            <nav className={styles.nav}>
                {navItems.map((item) => renderNavItem(item))}
            </nav>
        </div>
    );
};

export default SidebarFrame;
