import React, { useCallback } from "react";
import styles from "@components/minimap/styles.module.scss";

export interface MinimapHeading {
    id: string;
    text: string;
    level: number;
}

interface MinimapProps {
    headings: MinimapHeading[];
    activeId?: string;
    onNavigate?: (id: string) => void;
    theme?: "light" | "dark";
}

const Minimap: React.FC<MinimapProps> = ({ headings, activeId, onNavigate, theme = "light" }) => {
    const handleClick = useCallback(
        (id: string) => {
            if (onNavigate) {
                onNavigate(id);
            }
        },
        [onNavigate]
    );

    const isDark = theme === "dark";

    return (
        <div className={`${styles.minimap} ${isDark ? styles.dark : ""}`}>
            <div className={styles.minimap_header}>Quick Navigation</div>
            <div className={styles.minimap_content}>
                {headings.map((heading) => (
                    <div
                        key={heading.id}
                        className={`${styles.minimap_item} ${styles[`level_${heading.level}`]} ${activeId === heading.id ? styles.active : ""
                            }`}
                        onClick={() => handleClick(heading.id)}
                        title={heading.text}
                    >
                        <span className={styles.indicator} />
                        <span className={styles.text}>{heading.text}</span>
                    </div>
                ))}
            </div>
        </div>
    );
};

export default Minimap;
