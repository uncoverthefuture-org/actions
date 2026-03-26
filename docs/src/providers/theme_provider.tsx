import React, { createContext, useContext, useState, useEffect, useCallback } from "react";

// Match the storage key from uncover-account
const THEME_STORAGE_KEY = "@uncover.theme.local.storage";

export type ThemeMode = "light" | "dark";

interface ThemeColors {
    primary: string;
    primary_tint_1: string;
    secondary: string;
    tertiary: string;
    danger: string;
    warning: string;
    success: string;
    disabled: string;
    grey_1: string;
    grey_2: string;
    grey_3: string;
    grey_4: string;
    grey_5: string;
    off_black_1: string;
    off_black_2: string;
    white: string;
    // Additional for docs-specific theming
    background: string;
    text: string;
    border: string;
}

const lightColors: ThemeColors = {
    primary: "#005E5E",
    primary_tint_1: "#C5F6E5",
    secondary: "#F8AB29",
    tertiary: "#FF8749",
    danger: "#FF4D4F",
    warning: "#FAAD14",
    success: "#73D13D",
    disabled: "#D9D9D9",
    grey_1: "#FAFAFA",
    grey_2: "#F0F0F0",
    grey_3: "#D9D9D9",
    grey_4: "#8C8C8C",
    grey_5: "#595959",
    off_black_1: "#595959",
    off_black_2: "#141414",
    white: "#FFFFFF",
    background: "#FFFFFF",
    text: "#222222",
    border: "rgba(0, 0, 0, 0.08)",
};

const darkColors: ThemeColors = {
    primary: "#00A896",
    primary_tint_1: "#1a3a3a",
    secondary: "#F8AB29",
    tertiary: "#FF8749",
    danger: "#FF6B6B",
    warning: "#FAAD14",
    success: "#73D13D",
    disabled: "#4A4A4A",
    grey_1: "#1a1a1a",
    grey_2: "#2a2a2a",
    grey_3: "#3a3a3a",
    grey_4: "#8C8C8C",
    grey_5: "#BFBFBF",
    off_black_1: "#BFBFBF",
    off_black_2: "#F0F0F0",
    white: "#1a1a1a",
    background: "#1a1a1a",
    text: "#E8E8E8",
    border: "rgba(255, 255, 255, 0.1)",
};

interface ThemeContextValue {
    mode: ThemeMode;
    colors: ThemeColors;
    toggleTheme: () => void;
    setTheme: (mode: ThemeMode) => void;
}

const ThemeContext = createContext<ThemeContextValue | undefined>(undefined);

export const ThemeProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
    const [mode, setMode] = useState<ThemeMode>(() => {
        try {
            const stored = localStorage.getItem(THEME_STORAGE_KEY);
            return stored === "dark" ? "dark" : "light";
        } catch {
            return "light";
        }
    });

    const colors = mode === "dark" ? darkColors : lightColors;

    useEffect(() => {
        try {
            localStorage.setItem(THEME_STORAGE_KEY, mode);
        } catch {
            // Ignore localStorage errors
        }
    }, [mode]);

    const toggleTheme = useCallback(() => {
        setMode((prev) => (prev === "dark" ? "light" : "dark"));
    }, []);

    const setTheme = useCallback((newMode: ThemeMode) => {
        setMode(newMode);
    }, []);

    return (
        <ThemeContext.Provider value={{ mode, colors, toggleTheme, setTheme }}>
            {children}
        </ThemeContext.Provider>
    );
};

export const useTheme = (): ThemeContextValue => {
    const context = useContext(ThemeContext);
    if (!context) {
        throw new Error("useTheme must be used within ThemeProvider");
    }
    return context;
};

export default ThemeProvider;
