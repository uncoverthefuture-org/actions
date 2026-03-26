/**
 * Documentation Content Frame Component
 * 
 * Displays markdown content.
 * 
 * Updates:
 * - Mouse movement tracking for parent glow effect
 * - Updated route mappings (/uncover-actions/)
 */

import React, { useState, useEffect, useCallback, useRef } from "react";
import styles from "@pages/frames/doc_content/styles.module.scss";
import MarkdownViewer, { Heading } from "@components/markdown_viewer";
import Minimap from "@components/minimap";
import sshContainerDeployContent from "@data/ssh_container_deploy.md?raw";

interface DocContentInput {
    route?: string;
    theme?: "light" | "dark";
}

const titleMap: Record<string, string> = {
    "/": "Documentation",
    "/uncover-actions/ssh-container-deploy": "SSH Container Deploy",
};

const contentMap: Record<string, string> = {
    "/": "# Welcome to Uncover Docs\n\nSelect a topic from the sidebar to get started.",
    "/uncover-actions/ssh-container-deploy": sshContainerDeployContent,
};

const DocContentFrame: React.FC = () => {
    const [route, setRoute] = useState<string>("/");
    const [theme, setTheme] = useState<"light" | "dark">("light");
    const [headings, setHeadings] = useState<Heading[]>([]);
    const [activeHeadingId, setActiveHeadingId] = useState<string>("");
    const contentRef = useRef<HTMLDivElement>(null);

    // Helper to send messages to parent
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

    useEffect(() => {
        const handleMessage = (event: MessageEvent) => {
            if (event.data?.type === "WINDOW_INPUT") {
                const input = event.data.payload?.data as DocContentInput | undefined;
                if (input?.route) {
                    setRoute(input.route);
                }
                if (input?.theme) {
                    setTheme(input.theme);
                }
            }
        };

        window.addEventListener("message", handleMessage);
        return () => window.removeEventListener("message", handleMessage);
    }, []);

    const handleHeadingsExtracted = useCallback((extracted: Heading[]) => {
        setHeadings(extracted);
        if (extracted.length > 0) {
            setActiveHeadingId(extracted[0].id);
        }
    }, []);

    const handleNavigate = useCallback((id: string) => {
        const element = document.getElementById(id);
        if (element && contentRef.current) {
            element.scrollIntoView({ behavior: "smooth", block: "start" });
            setActiveHeadingId(id);
        }
    }, []);

    useEffect(() => {
        const container = contentRef.current;
        if (!container) return;

        const handleScroll = () => {
            const scrollTop = container.scrollTop;
            let current = "";
            for (const heading of headings) {
                const element = document.getElementById(heading.id);
                if (element && element.offsetTop <= scrollTop + 100) {
                    current = heading.id;
                }
            }
            if (current && current !== activeHeadingId) {
                setActiveHeadingId(current);
            }
        };

        container.addEventListener("scroll", handleScroll);
        return () => container.removeEventListener("scroll", handleScroll);
    }, [headings, activeHeadingId]);

    const content = contentMap[route] || contentMap["/"];
    const title = titleMap[route] || "Documentation";
    const isDark = theme === "dark";

    return (
        <div className={`${styles.doc_content} ${isDark ? styles.dark : ""}`}>
            <div className={styles.header}>
                <h1 className={styles.header_title}>{title}</h1>
            </div>
            <div className={styles.content_wrapper}>
                <div className={styles.content_area} ref={contentRef}>
                    <MarkdownViewer
                        content={content}
                        onHeadingsExtracted={handleHeadingsExtracted}
                        theme={theme}
                    />
                </div>
                <Minimap
                    headings={headings}
                    activeId={activeHeadingId}
                    onNavigate={handleNavigate}
                    theme={theme}
                />
            </div>
        </div>
    );
};

export default DocContentFrame;
