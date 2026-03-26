import { useState, useCallback, useRef, useEffect } from "react";

interface EdgeGlow {
    top: { active: boolean; position: number; intensity: number };
    right: { active: boolean; position: number; intensity: number };
    bottom: { active: boolean; position: number; intensity: number };
    left: { active: boolean; position: number; intensity: number };
}

interface UseEdgeGlowOptions {
    threshold?: number; // Distance from edge to trigger glow (px)
    spread?: number; // Spread of glow along edge (px)
}

const defaultEdge = { active: false, position: 0, intensity: 0 };

export const useEdgeGlow = (options: UseEdgeGlowOptions = {}) => {
    const { threshold = 50, spread = 100 } = options;
    const containerRef = useRef<HTMLDivElement>(null);
    const [glowState, setGlowState] = useState<EdgeGlow>({
        top: { ...defaultEdge },
        right: { ...defaultEdge },
        bottom: { ...defaultEdge },
        left: { ...defaultEdge },
    });

    const handleMouseMove = useCallback(
        (e: MouseEvent) => {
            const container = containerRef.current;
            if (!container) return;

            const rect = container.getBoundingClientRect();
            const x = e.clientX - rect.left;
            const y = e.clientY - rect.top;

            const distTop = y;
            const distBottom = rect.height - y;
            const distLeft = x;
            const distRight = rect.width - x;

            const calcIntensity = (dist: number) =>
                dist < threshold ? 1 - dist / threshold : 0;

            setGlowState({
                top: {
                    active: distTop < threshold,
                    position: (x / rect.width) * 100,
                    intensity: calcIntensity(distTop),
                },
                bottom: {
                    active: distBottom < threshold,
                    position: (x / rect.width) * 100,
                    intensity: calcIntensity(distBottom),
                },
                left: {
                    active: distLeft < threshold,
                    position: (y / rect.height) * 100,
                    intensity: calcIntensity(distLeft),
                },
                right: {
                    active: distRight < threshold,
                    position: (y / rect.height) * 100,
                    intensity: calcIntensity(distRight),
                },
            });
        },
        [threshold]
    );

    const handleMouseLeave = useCallback(() => {
        setGlowState({
            top: { ...defaultEdge },
            right: { ...defaultEdge },
            bottom: { ...defaultEdge },
            left: { ...defaultEdge },
        });
    }, []);

    useEffect(() => {
        const container = containerRef.current;
        if (!container) return;

        container.addEventListener("mousemove", handleMouseMove);
        container.addEventListener("mouseleave", handleMouseLeave);

        return () => {
            container.removeEventListener("mousemove", handleMouseMove);
            container.removeEventListener("mouseleave", handleMouseLeave);
        };
    }, [handleMouseMove, handleMouseLeave]);

    return { containerRef, glowState, spread };
};

export default useEdgeGlow;
