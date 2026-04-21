import { type TagCount } from "../lib/api";

interface Props {
  totals: Record<string, number>;
  tagCounts: TagCount[];
  activeKind: string | null;
  activeTag: string | null;
  onKind: (k: string | null) => void;
  onTag: (t: string | null) => void;
  onOpenCapture: () => void;
}

const KINDS: { key: string; label: string }[] = [
  { key: "", label: "Tudo" },
  { key: "image", label: "Imagens" },
  { key: "video", label: "Vídeos" },
  { key: "article", label: "Artigos" },
  { key: "tweet", label: "Tweets" },
  { key: "bookmark", label: "Bookmarks" },
  { key: "note", label: "Notas" },
  { key: "pdf", label: "PDFs" },
];

export function Sidebar({
  totals,
  tagCounts,
  activeKind,
  activeTag,
  onKind,
  onTag,
  onOpenCapture,
}: Props) {
  const total = Object.values(totals).reduce((a, b) => a + b, 0);

  return (
    <aside className="flex h-screen w-56 flex-col border-r border-paper-border bg-paper-sidebar">
      <div className="border-b border-paper-border px-5 py-4">
        <div className="text-lg font-bold text-paper-ink">Hypomnemata</div>
        <button
          type="button"
          onClick={onOpenCapture}
          className="mt-3 w-full rounded-md bg-paper-accent px-3 py-1.5 text-xs font-medium text-paper-card hover:opacity-90"
        >
          Nova captura <span className="opacity-70">⌘K</span>
        </button>
      </div>

      <nav className="flex-1 overflow-y-auto px-3 py-3">
        {KINDS.map(({ key, label }) => {
          const count = key === "" ? total : totals[key] || 0;
          const isActive = (activeKind || "") === key;
          return (
            <button
              key={key || "all"}
              type="button"
              onClick={() => onKind(key || null)}
              className={`flex w-full items-center justify-between rounded px-3 py-1.5 text-sm transition-colors ${
                isActive
                  ? "bg-paper-tag text-paper-ink"
                  : "text-paper-mid hover:bg-paper-card"
              }`}
            >
              <span>{label}</span>
              <span className="text-xs">{count}</span>
            </button>
          );
        })}

        {tagCounts.length > 0 && (
          <>
            <div className="mx-2 my-3 border-t border-dashed border-paper-border" />
            <div className="px-3 pb-1 text-xs font-medium uppercase tracking-wider text-paper-light">
              Etiquetas
            </div>
            <div className="flex flex-wrap gap-1 px-2 py-1">
              {tagCounts.map((t) => (
                <button
                  key={t.name}
                  type="button"
                  onClick={() => onTag(activeTag === t.name ? null : t.name)}
                  className={`rounded-full border px-2 py-0.5 text-xs transition-colors ${
                    activeTag === t.name
                      ? "border-paper-accent bg-paper-accent text-paper-card"
                      : "border-paper-border bg-paper-tag text-paper-mid hover:bg-paper-card"
                  }`}
                >
                  {t.name} <span className="opacity-60">{t.count}</span>
                </button>
              ))}
            </div>
          </>
        )}
      </nav>
    </aside>
  );
}
