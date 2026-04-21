import { useCallback, useEffect, useRef, useState } from "react";
import { api, type Item, type TagCount } from "../lib/api";
import { Card } from "../components/Card";
import { Sidebar } from "../components/Sidebar";
import { Searchbar } from "../components/Searchbar";

interface Props {
  onOpenDetail: (id: string) => void;
  onOpenCapture: () => void;
  reloadKey: number;
}

export function Library({ onOpenDetail, onOpenCapture, reloadKey }: Props) {
  const [items, setItems] = useState<Item[]>([]);
  const [totals, setTotals] = useState<Record<string, number>>({});
  const [tagCounts, setTagCounts] = useState<TagCount[]>([]);
  const [activeKind, setActiveKind] = useState<string | null>(null);
  const [activeTag, setActiveTag] = useState<string | null>(null);
  const [query, setQuery] = useState("");
  const [loading, setLoading] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const gridRef = useRef<HTMLDivElement>(null);
  const cols = useMasonryCols(gridRef);

  const refresh = useCallback(async () => {
    setLoading(true);
    setErr(null);
    try {
      if (query.trim()) {
        const r = await api.search(query.trim());
        setItems(r.items);
      } else {
        const r = await api.listItems({
          kind: activeKind || undefined,
          tag: activeTag || undefined,
          limit: 200,
        });
        setItems(r.items);
      }

      // Totals by kind (no kind filter)
      const kinds = ["image", "video", "article", "tweet", "bookmark", "note", "pdf"];
      const counts = await Promise.all(
        kinds.map((k) => api.listItems({ kind: k, limit: 1 })),
      );
      const totalsMap: Record<string, number> = {};
      kinds.forEach((k, i) => (totalsMap[k] = counts[i].total));
      setTotals(totalsMap);

      const tg = await api.tags();
      setTagCounts(tg);
    } catch (e) {
      setErr(String(e));
    } finally {
      setLoading(false);
    }
  }, [activeKind, activeTag, query]);

  useEffect(() => {
    void refresh();
  }, [refresh, reloadKey]);

  return (
    <div className="flex h-screen">
      <Sidebar
        totals={totals}
        tagCounts={tagCounts}
        activeKind={activeKind}
        activeTag={activeTag}
        onKind={(k) => {
          setActiveKind(k);
          setQuery("");
        }}
        onTag={(t) => {
          setActiveTag(t);
          setQuery("");
        }}
        onOpenCapture={onOpenCapture}
      />

      <main className="flex-1 overflow-hidden">
        <Searchbar
          value={query}
          onChange={setQuery}
          onOpenCapture={onOpenCapture}
        />
        <div className="h-[calc(100vh-57px)] overflow-y-auto px-6 py-5">
          <div className="mb-4 flex items-center gap-3 text-sm text-paper-mid">
            <span className="font-medium text-paper-ink">
              {query
                ? `Busca: "${query}"`
                : activeTag
                  ? `#${activeTag}`
                  : activeKind
                    ? labelFor(activeKind)
                    : "Recentes"}
            </span>
            <span className="text-xs">
              {loading ? "carregando..." : `${items.length} ${items.length === 1 ? "item" : "itens"}`}
            </span>
          </div>

          {err && (
            <div className="mb-4 rounded-md bg-red-50 px-4 py-3 text-sm text-red-700">
              {err}
            </div>
          )}

          {items.length === 0 && !loading ? (
            <div className="mt-24 text-center text-sm text-paper-mid">
              <div className="mb-2">nada aqui ainda.</div>
              <button
                type="button"
                onClick={onOpenCapture}
                className="rounded-md bg-paper-accent px-4 py-2 text-sm text-paper-card hover:opacity-90"
              >
                Capturar algo (⌘K)
              </button>
            </div>
          ) : (
            <div ref={gridRef} className="flex gap-4">
              {Array.from({ length: cols }, (_, colIdx) => (
                <div key={colIdx} className="flex min-w-0 flex-1 flex-col gap-4">
                  {items
                    .filter((_, i) => i % cols === colIdx)
                    .map((it) => (
                      <Card key={it.id} item={it} onClick={() => onOpenDetail(it.id)} />
                    ))}
                </div>
              ))}
            </div>
          )}
        </div>
      </main>
    </div>
  );
}

function useMasonryCols(ref: React.RefObject<HTMLDivElement>): number {
  const [cols, setCols] = useState(3);
  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    const obs = new ResizeObserver(([entry]) => {
      const w = entry.contentRect.width;
      setCols(w >= 1280 ? 4 : w >= 900 ? 3 : 2);
    });
    obs.observe(el);
    return () => obs.disconnect();
  }, [ref]);
  return cols;
}

function labelFor(kind: string): string {
  const map: Record<string, string> = {
    image: "Imagens",
    video: "Vídeos",
    article: "Artigos",
    tweet: "Tweets",
    bookmark: "Bookmarks",
    note: "Notas",
    pdf: "PDFs",
  };
  return map[kind] || kind;
}
