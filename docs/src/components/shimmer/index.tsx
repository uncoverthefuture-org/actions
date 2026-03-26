import React from "react";
import styles from "@components/shimmer/styles.module.scss";

interface ShimmerProps {
    width?: string;
    height?: string;
    borderRadius?: string;
}

const Shimmer: React.FC<ShimmerProps> = ({
    width = "100%",
    height = "100%",
    borderRadius = "8px",
}) => {
    return (
        <div
            className={styles.shimmer}
            style={{
                width,
                height,
                borderRadius,
            }}
        />
    );
};

export default Shimmer;
