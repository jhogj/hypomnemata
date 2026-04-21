import { useEffect, useRef } from "react";

interface Props {
  value: string;
  onChange: (v: string) => void;
  onOpenCapture: () => void;
}

export function Searchbar({ value, onChange, onOpenCapture }: Props) {
  const ref = useRef<HTMLInputElement>(null);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      const meta = e.metaKey || e.ctrlKey;
      if (meta && e.key.toLowerCase() === "k") {
        e.preventDefault();
        onOpenCapture();
      }
      if (meta && e.key === "/") {
        e.preventDefault();
        ref.current?.focus();
      }
    };
    document.addEventListener("keydown", onKey);
    return () => document.removeEventListener("keydown", onKey);
  }, [onOpenCapture]);

  return (
    <div className="flex items-center gap-3 border-b border-paper-border bg-paper-bg px-6 py-3">
      <div className="relative flex-1">
        <svg
          className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-paper-light"
          viewBox="0 0 20 20"
          fill="none"
          stroke="currentColor"
          strokeWidth="1.8"
        >
          <circle cx="9" cy="9" r="6" />
          <path d="m14 14 4 4" strokeLinecap="round" />
        </svg>
        <input
          ref={ref}
          type="search"
          placeholder="Buscar em Hypomnemata..."
          value={value}
          onChange={(e) => onChange(e.target.value)}
          className="w-full rounded-full border border-paper-border bg-paper-card py-2 pl-10 pr-24 text-sm text-paper-ink placeholder:text-paper-light focus:border-paper-accent focus:outline-none focus:ring-1 focus:ring-paper-accent"
        />
        <span className="absolute right-3 top-1/2 -translate-y-1/2 rounded border border-paper-border bg-paper-tag px-1.5 py-0.5 text-xs text-paper-mid">
          ⌘K captura
        </span>
      </div>
    </div>
  );
}
