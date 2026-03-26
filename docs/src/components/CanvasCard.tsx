import React, { useEffect, useRef, useState } from "react";
import styles from "@components/CanvasCard.module.scss";

type CanvasCardProps = {
  containerRef: React.RefObject<HTMLElement | null>;
  initialX?: number;
  initialY?: number;
  title?: string;
  onClose?: () => void;
  children?: React.ReactNode;
};

const CanvasCard: React.FC<CanvasCardProps> = ({
  containerRef,
  initialX = 24,
  initialY = 96,
  title = "Card",
  onClose,
  children,
}) => {
  const [pos, setPos] = useState({ x: initialX, y: initialY });
  const [dragging, setDragging] = useState(false);
  const [offset, setOffset] = useState({ x: 0, y: 0 });
  const cardRef = useRef<HTMLDivElement>(null);
  const frameRef = useRef<number | null>(null);
  const pendingRef = useRef<{ x: number; y: number } | null>(null);

  const startDrag = (clientX: number, clientY: number) => {
    if (!cardRef.current) return;
    const rect = cardRef.current.getBoundingClientRect();
    setOffset({ x: clientX - rect.left, y: clientY - rect.top });
    setDragging(true);
  };

  useEffect(() => {
    if (!dragging) return;

    const handleMove = (clientX: number, clientY: number) => {
      const container = containerRef.current;
      const card = cardRef.current;
      if (!container || !card) return;
      const cRect = container.getBoundingClientRect();
      const cardRect = card.getBoundingClientRect();
      const maxX = Math.max(0, cRect.width - cardRect.width);
      const maxY = Math.max(0, cRect.height - cardRect.height);
      const nextX = Math.min(Math.max(0, clientX - cRect.left - offset.x), maxX);
      const nextY = Math.min(Math.max(0, clientY - cRect.top - offset.y), maxY);

      // Batch updates to next animation frame for snappier motion
      pendingRef.current = { x: nextX, y: nextY };
      if (frameRef.current == null) {
        frameRef.current = requestAnimationFrame(() => {
          if (pendingRef.current) {
            setPos(pendingRef.current);
            pendingRef.current = null;
          }
          frameRef.current = null;
        });
      }
    };

    const onMouseMove = (e: MouseEvent) => {
      handleMove(e.clientX, e.clientY);
    };
    const onTouchMove = (e: TouchEvent) => {
      if (e.touches && e.touches[0]) {
        handleMove(e.touches[0].clientX, e.touches[0].clientY);
      }
    };
    const endDrag = () => setDragging(false);

    window.addEventListener("mousemove", onMouseMove);
    window.addEventListener("touchmove", onTouchMove, { passive: true });
    window.addEventListener("mouseup", endDrag);
    window.addEventListener("touchend", endDrag);
    window.addEventListener("touchcancel", endDrag);

    return () => {
      window.removeEventListener("mousemove", onMouseMove);
      window.removeEventListener("touchmove", onTouchMove as any);
      window.removeEventListener("mouseup", endDrag);
      window.removeEventListener("touchend", endDrag);
      window.removeEventListener("touchcancel", endDrag);
      if (frameRef.current != null) {
        cancelAnimationFrame(frameRef.current);
        frameRef.current = null;
      }
    };
  }, [dragging, containerRef, offset.x, offset.y]);

  const onMouseDown = (e: React.MouseEvent) => {
    e.preventDefault();
    startDrag(e.clientX, e.clientY);
  };

  const onTouchStart = (e: React.TouchEvent) => {
    if (e.touches && e.touches[0]) {
      startDrag(e.touches[0].clientX, e.touches[0].clientY);
    }
  };

  return (
    <div
      ref={cardRef}
      className={styles.canvasCard + (dragging ? " " + styles.dragging : "")}
      style={{ transform: `translate3d(${pos.x}px, ${pos.y}px, 0)`, zIndex: dragging ? 10 : 1 }}
      role="group"
      aria-label={title}
    >
      <div className={styles.header} onMouseDown={onMouseDown} onTouchStart={onTouchStart}>
        <div className={styles.title}>{title}</div>
        <button
          type="button"
          className={styles.close}
          onMouseDown={(e) => { e.stopPropagation(); }}
          onClick={(e) => { e.stopPropagation(); onClose && onClose(); }}
          aria-label="Close"
        >
          ×
        </button>
      </div>
      <div className={styles.body}>{children}</div>
    </div>
  );
};

export default CanvasCard;
