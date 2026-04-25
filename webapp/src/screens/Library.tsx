import { useCallback, useEffect, useRef, useState } from "react";
import { api, type FolderOut, type Item, type TagCount } from "../lib/api";
import { Card } from "../components/Card";
import { ListView } from "../components/ListView";
import { Sidebar } from "../components/Sidebar";
import { Searchbar } from "../components/Searchbar";
import { SelectionToolbar } from "../components/SelectionToolbar";

interface Props {
  onOpenDetail: (id: string, videoTime?: number) => void;
  onOpenCapture: () => void;
  reloadKey: number;
}

export function Library({ onOpenDetail, onOpenCapture, reloadKey }: Props) {
  const [items, setItems] = useState<Item[]>([]);
  const [totals, setTotals] = useState<Record<string, number>>({});
  const [tagCounts, setTagCounts] = useState<TagCount[]>([]);
  const [folders, setFolders] = useState<FolderOut[]>([]);
  const [storageBytes, setStorageBytes] = useState<number | null>(null);
  const [activeKind, setActiveKind] = useState<string | null>(null);
  const [activeTag, setActiveTag] = useState<string | null>(null);
  const [activeFolder, setActiveFolder] = useState<string | null>(null);
  const [query, setQuery] = useState("");
  const [loading, setLoading] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [viewMode, setViewMode] = useState<"grid" | "list">(() => {
    return (localStorage.getItem("hypomnemata_view_mode") as "grid" | "list") || "grid";
  });
  const [selectionMode, setSelectionMode] = useState(false);
  const [selectedItems, setSelectedItems] = useState<Set<string>>(new Set());
  const [draggingItemId, setDraggingItemId] = useState<string | null>(null);

  const gridRef = useRef<HTMLDivElement>(null);
  const cols = useMasonryCols(gridRef);

  // Esc cancela modo seleção
  useEffect(() => {
    function onKey(e: KeyboardEvent) {
      if (e.key === "Escape" && selectionMode) exitSelection();
    }
    document.addEventListener("keydown", onKey);
    return () => document.removeEventListener("keydown", onKey);
  }, [selectionMode]);

  function toggleViewMode(mode: "grid" | "list") {
    setViewMode(mode);
    localStorage.setItem("hypomnemata_view_mode", mode);
  }

  function toggleSelection(id: string) {
    setSelectedItems((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  }

  function exitSelection() {
    setSelectionMode(false);
    setSelectedItems(new Set());
  }

  const refreshFolders = useCallback(async () => {
    try {
      setFolders(await api.listFolders());
    } catch {}
  }, []);

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
          folder: activeFolder || undefined,
          limit: 200,
        });
        setItems(r.items);
      }

      const kinds = ["image", "video", "article", "tweet", "bookmark", "note", "pdf"];
      const counts = await Promise.all(kinds.map((k) => api.listItems({ kind: k, limit: 1 })));
      const totalsMap: Record<string, number> = {};
      kinds.forEach((k, i) => (totalsMap[k] = counts[i].total));
      setTotals(totalsMap);

      setTagCounts(await api.tags());
      await refreshFolders();

      try {
        const s = await api.storageInfo();
        setStorageBytes(s.total_bytes);
      } catch {}
    } catch (e) {
      setErr(String(e));
    } finally {
      setLoading(false);
    }
  }, [activeKind, activeTag, activeFolder, query, refreshFolders]);

  useEffect(() => { void refresh(); }, [refresh, reloadKey]);

  const hasPending = items.some(
    (it) => it.download_status === "pending" || it.ocr_status === "pending",
  );
  useEffect(() => {
    if (!hasPending) return;
    const id = setInterval(() => void refresh(), 5000);
    return () => clearInterval(id);
  }, [hasPending, refresh]);

  async function handleDeleteSelected() {
    if (!confirm(`Excluir ${selectedItems.size} ${selectedItems.size === 1 ? "item" : "itens"}?`)) return;
    try {
      await Promise.all([...selectedItems].map((id) => api.deleteItem(id)));
      exitSelection();
      void refresh();
    } catch (e) {
      setErr(String(e));
    }
  }

  async function handleAddToFolder(folderId: string) {
    try {
      await api.addItemsToFolder(folderId, [...selectedItems]);
      exitSelection();
      await refreshFolders();
    } catch (e) {
      setErr(String(e));
    }
  }

  async function handleCreateAndAdd(name: string) {
    try {
      const folder = await api.createFolder(name);
      await api.addItemsToFolder(folder.id, [...selectedItems]);
      exitSelection();
      await refreshFolders();
    } catch (e) {
      setErr(String(e));
    }
  }

  const activeFolderLabel = activeFolder
    ? (folders.find((f) => f.id === activeFolder)?.name ?? "Pasta")
    : null;

  return (
    <div className="flex h-screen">
      <Sidebar
        totals={totals}
        tagCounts={tagCounts}
        folders={folders}
        activeKind={activeKind}
        activeTag={activeTag}
        activeFolder={activeFolder}
        storageBytes={storageBytes}
        draggingItemId={draggingItemId}
        onKind={(k) => { setActiveKind(k); setActiveFolder(null); setQuery(""); }}
        onTag={(t) => { setActiveTag(t); setActiveFolder(null); setQuery(""); }}
        onFolder={(id) => { setActiveFolder(id); setActiveKind(null); setActiveTag(null); setQuery(""); }}
        onFoldersChange={refreshFolders}
        onOpenCapture={onOpenCapture}
      />

      <main className="flex-1 overflow-hidden">
        <Searchbar value={query} onChange={setQuery} onOpenCapture={onOpenCapture} />
        <div className="h-[calc(100vh-57px)] overflow-y-auto px-6 py-5">
          <div className="mb-4 flex items-center justify-between text-sm text-paper-mid">
            <div className="flex items-center gap-3">
              <span className="font-medium text-paper-ink">
                {query
                  ? `Busca: "${query}"`
                  : activeFolderLabel
                    ? activeFolderLabel
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
            <div className="flex items-center gap-2">
              {/* Botão modo seleção */}
              <button
                type="button"
                onClick={() => { setSelectionMode((v) => !v); setSelectedItems(new Set()); }}
                title="Selecionar itens"
                className={`rounded p-1.5 transition-colors ${selectionMode ? "bg-paper-accent/15 text-paper-accent" : "text-paper-mid hover:bg-paper-tag hover:text-paper-ink"}`}
              >
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" className="h-4 w-4">
                  <path strokeLinecap="round" strokeLinejoin="round" d="M9 12.75L11.25 15 15 9.75M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
                </svg>
              </button>
              {/* Toggle grid/lista */}
              <div className="flex items-center gap-1 rounded bg-paper-tag p-0.5">
                <button
                  onClick={() => toggleViewMode("grid")}
                  className={`rounded p-1 transition-colors ${viewMode === "grid" ? "bg-paper-card shadow-sm text-paper-ink" : "text-paper-mid hover:text-paper-ink"}`}
                  title="Visão em Grid"
                >
                  <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                    <rect x="3" y="3" width="7" height="7"></rect><rect x="14" y="3" width="7" height="7"></rect>
                    <rect x="14" y="14" width="7" height="7"></rect><rect x="3" y="14" width="7" height="7"></rect>
                  </svg>
                </button>
                <button
                  onClick={() => toggleViewMode("list")}
                  className={`rounded p-1 transition-colors ${viewMode === "list" ? "bg-paper-card shadow-sm text-paper-ink" : "text-paper-mid hover:text-paper-ink"}`}
                  title="Visão em Lista"
                >
                  <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                    <line x1="8" y1="6" x2="21" y2="6"></line><line x1="8" y1="12" x2="21" y2="12"></line>
                    <line x1="8" y1="18" x2="21" y2="18"></line><line x1="3" y1="6" x2="3.01" y2="6"></line>
                    <line x1="3" y1="12" x2="3.01" y2="12"></line><line x1="3" y1="18" x2="3.01" y2="18"></line>
                  </svg>
                </button>
              </div>
            </div>
          </div>

          {err && (
            <div className="mb-4 rounded-md bg-red-50 px-4 py-3 text-sm text-red-700">{err}</div>
          )}

          {items.length === 0 && !loading ? (
            <div className="mt-24 text-center text-sm text-paper-mid">
              <div className="mb-2">
                {activeFolder ? "Nenhum item nesta pasta ainda." : "nada aqui ainda."}
              </div>
              {!activeFolder && (
                <button type="button" onClick={onOpenCapture} className="rounded-md bg-paper-accent px-4 py-2 text-sm text-paper-card hover:opacity-90">
                  Capturar algo (⌘K)
                </button>
              )}
            </div>
          ) : viewMode === "list" ? (
            <ListView items={items} onClick={(item) => onOpenDetail(item.id)} onDelete={async (item) => {
              if (!confirm("Excluir este item?")) return;
              try { await api.deleteItem(item.id); void refresh(); } catch (e) { setErr(String(e)); }
            }} />
          ) : (
            <div ref={gridRef} className="flex gap-4">
              {Array.from({ length: cols }, (_, colIdx) => (
                <div key={colIdx} className="flex min-w-0 flex-1 flex-col gap-4">
                  {items
                    .filter((_, i) => i % cols === colIdx)
                    .map((it) => (
                      <Card
                        key={it.id}
                        item={it}
                        selectionMode={selectionMode}
                        selected={selectedItems.has(it.id)}
                        onToggleSelect={() => toggleSelection(it.id)}
                        onDragStart={(id) => setDraggingItemId(id)}
                        onDragEnd={() => setDraggingItemId(null)}
                        onClick={(vt) => { if (!selectionMode) onOpenDetail(it.id, vt); }}
                        onDelete={async () => {
                          try { await api.deleteItem(it.id); void refresh(); } catch (e) { setErr(String(e)); }
                        }}
                      />
                    ))}
                </div>
              ))}
            </div>
          )}
        </div>
      </main>

      {selectionMode && selectedItems.size > 0 && (
        <SelectionToolbar
          count={selectedItems.size}
          folders={folders}
          onAddToFolder={handleAddToFolder}
          onCreateAndAdd={handleCreateAndAdd}
          onDeleteSelected={handleDeleteSelected}
          onCancel={exitSelection}
        />
      )}
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
    image: "Imagens", video: "Vídeos", article: "Artigos",
    tweet: "Tweets", bookmark: "Bookmarks", note: "Notas", pdf: "PDFs",
  };
  return map[kind] || kind;
}
