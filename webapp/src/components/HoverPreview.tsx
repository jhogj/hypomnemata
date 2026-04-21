import { useState, useRef, useEffect } from "react";
import { createPortal } from "react-dom";

interface Props {
  imageUrl: string | null;
  children: React.ReactNode;
}

export function HoverPreview({ imageUrl, children }: Props) {
  const [hovered, setHovered] = useState(false);
  const [coords, setCoords] = useState({ top: 0, left: 0 });
  const timeoutRef = useRef<number | null>(null);
  const wrapperRef = useRef<HTMLDivElement>(null);

  const handleMouseEnter = () => {
    if (!imageUrl) return;
    timeoutRef.current = window.setTimeout(() => {
      if (wrapperRef.current) {
        const rect = wrapperRef.current.getBoundingClientRect();
        // Position preview to the right of the row, centered vertically relative to the row
        const top = rect.top + rect.height / 2;
        // If there's no space on the right, show on the left? For simplicity, we just show near the row
        setCoords({
          top: top,
          left: rect.left + rect.width / 4, // Show it overlapping the row, a bit to the right
        });
        setHovered(true);
      }
    }, 600);
  };

  const handleMouseLeave = () => {
    if (timeoutRef.current) clearTimeout(timeoutRef.current);
    setHovered(false);
  };

  useEffect(() => {
    return () => {
      if (timeoutRef.current) clearTimeout(timeoutRef.current);
    };
  }, []);

  return (
    <div
      ref={wrapperRef}
      onMouseEnter={handleMouseEnter}
      onMouseLeave={handleMouseLeave}
    >
      {children}
      {hovered &&
        imageUrl &&
        createPortal(
          <div
            className="fixed z-50 pointer-events-none rounded border border-paper-border bg-paper-card shadow-2xl overflow-hidden animate-in fade-in zoom-in-95 duration-200"
            style={{
              top: coords.top,
              left: coords.left,
              transform: "translateY(-50%)",
              maxWidth: "320px",
              maxHeight: "320px",
            }}
          >
            <img
              src={imageUrl}
              alt="preview"
              className="block max-w-full max-h-full object-cover"
            />
          </div>,
          document.body
        )}
    </div>
  );
}
