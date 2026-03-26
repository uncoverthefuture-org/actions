import React, { useEffect, useMemo } from "react";
import ReactMarkdown from "react-markdown";
import remarkGfm from "remark-gfm";
import styles from "@components/markdown_viewer/styles.module.scss";
import CodeBlock from "@components/code_block";

export interface Heading {
    id: string;
    text: string;
    level: number;
}

interface MarkdownViewerProps {
    content: string;
    onHeadingsExtracted?: (headings: Heading[]) => void;
    theme?: "light" | "dark";
}

const MarkdownViewer: React.FC<MarkdownViewerProps> = ({
    content,
    onHeadingsExtracted,
    theme = "light",
}) => {
    // Extract headings from content
    const headings = useMemo(() => {
        const headingRegex = /^(#{1,6})\s+(.+)$/gm;
        const extracted: Heading[] = [];
        let match;

        while ((match = headingRegex.exec(content)) !== null) {
            const level = match[1].length;
            const text = match[2].trim();
            const id = text
                .toLowerCase()
                .replace(/[^\w\s-]/g, "")
                .replace(/\s+/g, "-");
            extracted.push({ id, text, level });
        }

        return extracted;
    }, [content]);

    useEffect(() => {
        if (onHeadingsExtracted) {
            onHeadingsExtracted(headings);
        }
    }, [headings, onHeadingsExtracted]);

    // Custom heading renderer to add IDs
    const createHeading = (level: number) => {
        return ({ children }: { children?: React.ReactNode }) => {
            const text = String(children || "");
            const id = text
                .toLowerCase()
                .replace(/[^\w\s-]/g, "")
                .replace(/\s+/g, "-");

            return React.createElement(`h${level}`, { id }, children);
        };
    };

    const isDark = theme === "dark";

    return (
        <div className={`${styles.markdown_viewer} ${isDark ? styles.dark : ""}`}>
            <ReactMarkdown
                remarkPlugins={[remarkGfm]}
                components={{
                    h1: createHeading(1),
                    h2: createHeading(2),
                    h3: createHeading(3),
                    h4: createHeading(4),
                    h5: createHeading(5),
                    h6: createHeading(6),
                    table: ({ children }) => (
                        <div className={styles.table_wrapper}>
                            <table>{children}</table>
                        </div>
                    ),
                    code: ({ className, children, ...props }) => {
                        const isInline = !className;
                        const code = String(children || "").replace(/\n$/, "");

                        if (isInline) {
                            return (
                                <code className={styles.inline_code} {...props}>
                                    {children}
                                </code>
                            );
                        }

                        // Extract language from className (e.g., "language-bash")
                        const language = className?.replace("language-", "") || "";

                        return (
                            <CodeBlock
                                code={code}
                                language={language}
                                theme={theme}
                            />
                        );
                    },
                }}
            >
                {content}
            </ReactMarkdown>
        </div>
    );
};

export default MarkdownViewer;
