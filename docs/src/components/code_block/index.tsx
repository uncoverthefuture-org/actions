import React, { useState, useCallback } from "react";
import styles from "@components/code_block/styles.module.scss";

interface CodeBlockProps {
    code: string;
    language?: string;
    theme?: "light" | "dark";
}

const CodeBlock: React.FC<CodeBlockProps> = ({ code, language, theme = "light" }) => {
    const [copied, setCopied] = useState(false);

    const handleCopy = useCallback(async () => {
        try {
            await navigator.clipboard.writeText(code);
            setCopied(true);
            setTimeout(() => setCopied(false), 2000);
        } catch (err) {
            console.error("Failed to copy:", err);
        }
    }, [code]);

    const isDark = theme === "dark";

    return (
        <div className={`${styles.code_block_wrapper} ${isDark ? styles.dark : ""}`}>
            <div className={styles.code_header}>
                {language && <span className={styles.language}>{language}</span>}
                <button
                    className={styles.copy_button}
                    onClick={handleCopy}
                    title={copied ? "Copied!" : "Copy code"}
                >
                    {copied ? (
                        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                            <polyline points="20 6 9 17 4 12" />
                        </svg>
                    ) : (
                        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                            <rect x="9" y="9" width="13" height="13" rx="2" ry="2" />
                            <path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1" />
                        </svg>
                    )}
                </button>
            </div>
            <pre className={styles.code_content}>
                <code className={language ? `language-${language}` : ""}>
                    {code}
                </code>
            </pre>
        </div>
    );
};

export default CodeBlock;
