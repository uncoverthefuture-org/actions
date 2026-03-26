import React from "react";
import { Link } from "react-router-dom";
import styles from "@components/LogoCard.module.scss";

interface LogoCardProps {
  logoSrc: string;
  logoAlt: string;
  linkTo: string;
}

const LogoCard: React.FC<LogoCardProps> = ({ logoSrc, logoAlt, linkTo }) => {
  return (
    <Link className={styles.logoCard} to={linkTo}>
      <img src={logoSrc} alt={logoAlt} />
    </Link>
  );
};

export default LogoCard;
