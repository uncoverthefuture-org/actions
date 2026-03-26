/**
 * Window Component
 * 
 * Features:
 * - High-performance mouse tracking using direct DOM manipulation (no re-renders)
 * - Cross-frame mouse tracking (receives coordinates from iframe)
 * - Intelligent edge detection for glow intensity
 * - Loading shimmer
 * - Iframe encapsulation
 */

import React, { useEffect, useRef, useState, useCallback } from "react";
import styles from "@components/window/styles.module.scss";
import Shimmer from "@components/shimmer";

export interface WindowInputProps {
    dimensions?: { width?: string; height?: string };
    styles?: React.CSSProperties;
    data?: unknown;
    resizable?: boolean;
}

interface WindowProps {
    src: string;
    input?: WindowInputProps;
    onOutput?: (data: unknown) => void;
    className?: string;
}

const EDGE_THRESHOLD = 60; // Pixels from edge where glow starts

const Window: React.FC<WindowProps> = ({
    src,
    input = {},
    onOutput,
    className,
}) => {
    const iframeRef = useRef<HTMLIFrameElement>(null);
    const containerRef = useRef<HTMLDivElement>(null);
    const [isLoading, setIsLoading] = useState(true);

    // Timeout ref for preventing flicker on boundary crossing
    const leaveTimeoutRef = useRef<ReturnType<typeof setTimeout>>();

    const { dimensions, styles: customStyles, data, resizable = true } = input;

    /* --------------------------------------------------------------------------
       Glow Effect Logic (Direct DOM)
       -------------------------------------------------------------------------- */

    /**
     * Updates the glow effect based on mouse coordinates relative to the container.
     * @param x - Mouse X relative to container-left
     * @param y - Mouse Y relative to container-top
     */
    const updateGlow = useCallback((x: number, y: number) => {
        const container = containerRef.current;
        if (!container) return;

        // Clear any pending leave timeout since we have activity
        if (leaveTimeoutRef.current) {
            clearTimeout(leaveTimeoutRef.current);
            leaveTimeoutRef.current = undefined;
        }

        const rect = container.getBoundingClientRect();

        // Calculate distance to nearest edge
        const distLeft = x;
        const distRight = rect.width - x;
        const distTop = y;
        const distBottom = rect.height - y;
        const minEdgeDist = Math.min(distLeft, distRight, distTop, distBottom);

        // Calculate opacity based on proximity to edge
        // 0 at center (beyond threshold), 1 at edge
        let opacity = 0;
        if (minEdgeDist < EDGE_THRESHOLD) {
            opacity = 1 - (minEdgeDist / EDGE_THRESHOLD);
            opacity = Math.pow(opacity, 1.5); // Smoother falloff
        }

        // Apply styles directly to avoid React render cycle
        container.style.setProperty("--mouse-x", `${x}px`);
        container.style.setProperty("--mouse-y", `${y}px`);
        container.style.setProperty("--glow-opacity", opacity.toString());
    }, []);

    const handleContainerMouseMove = useCallback((e: React.MouseEvent) => {
        const container = containerRef.current;
        if (!container) return;
        const rect = container.getBoundingClientRect();
        updateGlow(e.clientX - rect.left, e.clientY - rect.top);
    }, [updateGlow]);

    const handleMouseLeave = useCallback(() => {
        const container = containerRef.current;
        if (!container) return;

        // Debounce the leave event to prevent flicker when crossing into iframe
        // or when events arrive out of order
        leaveTimeoutRef.current = setTimeout(() => {
            container.style.setProperty("--glow-opacity", "0");
        }, 50);
    }, []);

    /* --------------------------------------------------------------------------
       Iframe Communication
       -------------------------------------------------------------------------- */

    useEffect(() => {
        const iframe = iframeRef.current;
        if (!iframe || !iframe.contentWindow) return;

        const sendInput = () => {
            iframe.contentWindow?.postMessage(
                { type: "WINDOW_INPUT", payload: { data, styles: customStyles } },
                "*"
            );
        };

        if (!isLoading) {
            sendInput();
        }
    }, [data, customStyles, isLoading]);

    useEffect(() => {
        const handleMessage = (event: MessageEvent) => {
            if (event.data?.type === "WINDOW_OUTPUT") {
                const payload = event.data.payload;

                // Handle internal mouse tracking from iframe
                if (payload.action === "mousemove") {
                    // payload.x/y are client coordinates from inside iframe
                    // We treat them as relative to container since iframe fills container
                    updateGlow(payload.x, payload.y);
                    return;
                }

                // Forward other events to parent
                if (onOutput) {
                    onOutput(payload);
                }
            }
        };

        window.addEventListener("message", handleMessage);
        return () => window.removeEventListener("message", handleMessage);
    }, [onOutput, updateGlow]);

    const handleLoad = useCallback(() => {
        setIsLoading(false);
    }, []);

    const containerStyle: React.CSSProperties = {
        width: dimensions?.width || "100%",
        height: dimensions?.height || "100%",
        resize: resizable ? "both" : "none",
        ...customStyles,
    };

    return (
        <div
            ref={containerRef}
            className={`${styles.window_container} ${className || ""}`}
            style={containerStyle}
            onMouseMove={handleContainerMouseMove}
            onMouseLeave={handleMouseLeave}
        >
            {/* Spotlight Glow Layer */}
            <div className={styles.glow_spotlight} />

            {/* Content */}
            {isLoading && (
                <div className={styles.shimmer_overlay}>
                    <Shimmer />
                </div>
            )}
            <iframe
                ref={iframeRef}
                src={src}
                className={styles.iframe}
                onLoad={handleLoad}
                title="Window Frame"
            />
        </div>
    );
};

export default Window;
