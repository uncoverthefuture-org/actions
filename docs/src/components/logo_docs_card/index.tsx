import React from "react";
import { Link } from "react-router-dom";
import styles from "@components/logo_docs_card/styles.module.scss";

interface LogoDocsCardProps {
    logoSrc: string;
    logoAlt: string;
    linkTo: string;
    isDark?: boolean;
}

const LogoDocsCard: React.FC<LogoDocsCardProps> = ({ logoSrc, logoAlt, linkTo, isDark = false }) => {
    return (
        <div className={`${styles.logoDocsCard} ${isDark ? styles.dark : ""}`}>
            <Link className={styles.logoWrapper} to={linkTo}>
                <img src={logoSrc} alt={logoAlt} />
            </Link>
            <span className={styles.docsText}>Docs</span>
        </div>
    );
};

export default LogoDocsCard;
