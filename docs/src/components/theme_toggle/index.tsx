import React from "react";
import styles from "@components/theme_toggle/styles.module.scss";
import { useTheme } from "@/providers/theme_provider";

const ThemeToggle: React.FC = () => {
    const { mode, toggleTheme } = useTheme();
    const isDark = mode === "dark";

    return (
        <button
            className={styles.toggle}
            onClick={toggleTheme}
            title={isDark ? "Light mode" : "Dark mode"}
            aria-label={isDark ? "Switch to light mode" : "Switch to dark mode"}
        >
            {isDark ? "☀" : "◐"}
        </button>
    );
};

export default ThemeToggle;
