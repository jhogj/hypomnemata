import { useEffect, useRef, useState } from "react";
import { api, type FolderOut, type TagCount } from "../lib/api";

type BackupState = "idle" | "running" | "ok" | "error";

interface Props {
  totals: Record<string, number>;
  tagCounts: TagCount[];
  folders: FolderOut[];
  activeKind: string | null;
  activeTag: string | null;
  activeFolder: string | null;
  storageBytes: number | null;
  draggingItemId: string | null;
  onKind: (k: string | null) => void;
  onTag: (t: string | null) => void;
  onFolder: (id: string | null) => void;
  onFoldersChange: () => void;
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

function formatBytes(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  if (bytes < 1024 * 1024 * 1024) return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
  return `${(bytes / (1024 * 1024 * 1024)).toFixed(2)} GB`;
}

export function Sidebar({
  totals,
  tagCounts,
  folders,
  activeKind,
  activeTag,
  activeFolder,
  storageBytes,
  draggingItemId,
  onKind,
  onTag,
  onFolder,
  onFoldersChange,
  onOpenCapture,
}: Props) {
  const total = Object.values(totals).reduce((a, b) => a + b, 0);

  const [tagsOpen, setTagsOpen] = useState(true);
  const [creatingFolder, setCreatingFolder] = useState(false);
  const [backupState, setBackupState] = useState<BackupState>("idle");
  const [backupError, setBackupError] = useState<string | null>(null);
  const [backupConfigured, setBackupConfigured] = useState(false);
  const [lastBackup, setLastBackup] = useState<string | null>(() =>
    localStorage.getItem("hypo_last_backup")
  );
  const [newFolderName, setNewFolderName] = useState("");
  const [renamingId, setRenamingId] = useState<string | null>(null);
  const [renameValue, setRenameValue] = useState("");
  const [dragOverId, setDragOverId] = useState<string | null>(null);
  const createInputRef = useRef<HTMLInputElement>(null);
  const renameInputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    if (creatingFolder) createInputRef.current?.focus();
  }, [creatingFolder]);

  useEffect(() => {
    if (renamingId) renameInputRef.current?.focus();
  }, [renamingId]);

  useEffect(() => {
    api.backupStatus().then((s) => setBackupConfigured(s.configured)).catch(() => {});
  }, []);

  async function handleBackup() {
    if (!backupConfigured || backupState === "running") return;
    setBackupState("running");
    setBackupError(null);
    try {
      await api.triggerBackup();
      const now = new Date().toLocaleString("pt-BR");
      setLastBackup(now);
      localStorage.setItem("hypo_last_backup", now);
      setBackupState("ok");
      setTimeout(() => setBackupState("idle"), 3000);
    } catch (e) {
      setBackupError(String(e));
      setBackupState("error");
    }
  }

  async function submitCreate() {
    const name = newFolderName.trim();
    if (!name) { setCreatingFolder(false); return; }
    try {
      await api.createFolder(name);
      onFoldersChange();
    } catch {}
    setNewFolderName("");
    setCreatingFolder(false);
  }

  async function submitRename(id: string) {
    const name = renameValue.trim();
    if (name) {
      try { await api.renameFolder(id, name); onFoldersChange(); } catch {}
    }
    setRenamingId(null);
  }

  async function deleteFolder(id: string, name: string) {
    if (!confirm(`Excluir pasta "${name}"? Os itens não serão excluídos.`)) return;
    try { await api.deleteFolder(id); onFoldersChange(); } catch {}
    if (activeFolder === id) onFolder(null);
  }

  async function handleDrop(e: React.DragEvent, folderId: string) {
    e.preventDefault();
    setDragOverId(null);
    const itemId = e.dataTransfer.getData("item_id");
    if (!itemId) return;
    try { await api.addItemsToFolder(folderId, [itemId]); onFoldersChange(); } catch {}
  }

  return (
    <aside className="flex h-screen w-56 flex-col border-r border-paper-border bg-paper-sidebar">
      <div className="border-b border-paper-border px-5 py-4">
        <div className="flex items-center justify-center h-10 overflow-hidden mb-2 -ml-3">
          <img src="/marca.png" alt="Hypomnemata" className="w-[280px] max-w-none object-contain" />
        </div>
        <button
          type="button"
          onClick={onOpenCapture}
          className="mt-3 w-full rounded-md bg-paper-accent px-3 py-1.5 text-xs font-medium text-paper-card hover:opacity-90"
        >
          Nova captura <span className="opacity-70">⌘K</span>
        </button>
      </div>

      <nav className="flex-1 overflow-y-auto px-3 py-3">
        {/* Categorias */}
        {KINDS.map(({ key, label }) => {
          const count = key === "" ? total : totals[key] || 0;
          const isActive = !activeFolder && !activeTag && (activeKind || "") === key;
          return (
            <button
              key={key || "all"}
              type="button"
              onClick={() => onKind(key || null)}
              className={`flex w-full items-center justify-between rounded px-3 py-1.5 text-sm transition-colors ${
                isActive ? "bg-paper-tag text-paper-ink" : "text-paper-mid hover:bg-paper-card"
              }`}
            >
              <span>{label}</span>
              <span className="text-xs">{count}</span>
            </button>
          );
        })}

        {/* Pastas */}
        <div className="mx-2 my-3 border-t border-dashed border-paper-border" />
        <div className="flex items-center justify-between px-3 pb-1">
          <span className="text-xs font-medium uppercase tracking-wider text-paper-light">Pastas</span>
          <button
            type="button"
            onClick={() => setCreatingFolder(true)}
            title="Nova pasta"
            className="rounded p-0.5 text-paper-light hover:bg-paper-card hover:text-paper-mid"
          >
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" className="h-3.5 w-3.5">
              <path strokeLinecap="round" strokeLinejoin="round" d="M12 4.5v15m7.5-7.5h-15" />
            </svg>
          </button>
        </div>

        {folders.map((f) => {
          const isActive = activeFolder === f.id;
          const isDragOver = dragOverId === f.id && !!draggingItemId;
          return (
            <div
              key={f.id}
              onDragOver={(e) => { e.preventDefault(); setDragOverId(f.id); }}
              onDragLeave={() => setDragOverId(null)}
              onDrop={(e) => handleDrop(e, f.id)}
              className={`group flex items-center rounded px-3 py-1.5 transition-colors ${
                isDragOver
                  ? "bg-paper-accent/10 ring-1 ring-paper-accent"
                  : isActive
                    ? "bg-paper-tag text-paper-ink"
                    : "text-paper-mid hover:bg-paper-card"
              }`}
            >
              {renamingId === f.id ? (
                <input
                  ref={renameInputRef}
                  value={renameValue}
                  onChange={(e) => setRenameValue(e.target.value)}
                  onBlur={() => submitRename(f.id)}
                  onKeyDown={(e) => {
                    if (e.key === "Enter") submitRename(f.id);
                    if (e.key === "Escape") setRenamingId(null);
                  }}
                  className="min-w-0 flex-1 bg-transparent text-sm outline-none"
                  onClick={(e) => e.stopPropagation()}
                />
              ) : (
                <button
                  type="button"
                  onClick={() => onFolder(isActive ? null : f.id)}
                  className="flex min-w-0 flex-1 items-center gap-2 text-sm"
                >
                  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" className={`h-4 w-4 shrink-0 ${isActive ? "text-paper-accent" : "text-paper-light"}`}>
                    <path strokeLinecap="round" strokeLinejoin="round" d="M2.25 12.75V12A2.25 2.25 0 014.5 9.75h15A2.25 2.25 0 0121.75 12v.75m-8.69-6.44l-2.12-2.12a1.5 1.5 0 00-1.061-.44H4.5A2.25 2.25 0 002.25 6v12a2.25 2.25 0 002.25 2.25h15A2.25 2.25 0 0021.75 18V9a2.25 2.25 0 00-2.25-2.25h-5.379a1.5 1.5 0 01-1.06-.44z" />
                  </svg>
                  <span className="truncate">{f.name}</span>
                  <span className="ml-auto text-xs opacity-50">{f.item_count}</span>
                </button>
              )}
              {renamingId !== f.id && (
                <div className="ml-1 flex shrink-0 items-center gap-0.5 opacity-0 group-hover:opacity-100">
                  <button
                    type="button"
                    title="Renomear"
                    onClick={(e) => { e.stopPropagation(); setRenamingId(f.id); setRenameValue(f.name); }}
                    className="rounded p-0.5 hover:bg-paper-bg hover:text-paper-ink"
                  >
                    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" className="h-3.5 w-3.5">
                      <path strokeLinecap="round" strokeLinejoin="round" d="M16.862 4.487l1.687-1.688a1.875 1.875 0 112.652 2.652L10.582 16.07a4.5 4.5 0 01-1.897 1.13L6 18l.8-2.685a4.5 4.5 0 011.13-1.897l8.932-8.931z" />
                    </svg>
                  </button>
                  <button
                    type="button"
                    title="Excluir pasta"
                    onClick={(e) => { e.stopPropagation(); void deleteFolder(f.id, f.name); }}
                    className="rounded p-0.5 hover:bg-red-50 hover:text-red-500"
                  >
                    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" className="h-3.5 w-3.5">
                      <path strokeLinecap="round" strokeLinejoin="round" d="M6 18L18 6M6 6l12 12" />
                    </svg>
                  </button>
                </div>
              )}
            </div>
          );
        })}

        {creatingFolder && (
          <div className="mt-1 px-3">
            <input
              ref={createInputRef}
              value={newFolderName}
              onChange={(e) => setNewFolderName(e.target.value)}
              onBlur={submitCreate}
              onKeyDown={(e) => {
                if (e.key === "Enter") void submitCreate();
                if (e.key === "Escape") { setCreatingFolder(false); setNewFolderName(""); }
              }}
              placeholder="Nome da pasta"
              className="w-full rounded border border-paper-accent bg-paper-bg px-2 py-1.5 text-sm focus:outline-none"
            />
          </div>
        )}

        {folders.length === 0 && !creatingFolder && (
          <div className="px-3 py-1 text-xs text-paper-light">
            Nenhuma pasta ainda
          </div>
        )}

        {/* Etiquetas — colapsável, abaixo das pastas */}
        {tagCounts.length > 0 && (
          <>
            <div className="mx-2 my-3 border-t border-dashed border-paper-border" />
            <button
              type="button"
              onClick={() => setTagsOpen((v) => !v)}
              className="flex w-full items-center justify-between px-3 pb-1 text-xs font-medium uppercase tracking-wider text-paper-light hover:text-paper-mid"
            >
              <span>Etiquetas</span>
              <span>{tagsOpen ? "▾" : "▸"}</span>
            </button>
            {tagsOpen && (
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
            )}
          </>
        )}
      </nav>

      <div className="border-t border-paper-border px-5 py-3">
        {storageBytes != null && (
          <div className="mb-2 flex items-center gap-2 text-xs text-paper-mid">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" className="h-4 w-4 shrink-0">
              <path strokeLinecap="round" strokeLinejoin="round" d="M20.25 6.375c0 2.278-3.694 4.125-8.25 4.125S3.75 8.653 3.75 6.375m16.5 0c0-2.278-3.694-4.125-8.25-4.125S3.75 4.097 3.75 6.375m16.5 0v11.25c0 2.278-3.694 4.125-8.25 4.125s-8.25-1.847-8.25-4.125V6.375m16.5 0v3.75c0 2.278-3.694 4.125-8.25 4.125s-8.25-1.847-8.25-4.125v-3.75" />
            </svg>
            <span>{formatBytes(storageBytes)}</span>
          </div>
        )}
        <div className="flex items-center gap-2">
          <a
            href={api.exportBackupUrl()}
            target="_blank"
            rel="noreferrer"
            className="flex flex-1 items-center gap-2 rounded bg-paper-tag px-2 py-1 text-xs text-paper-mid hover:bg-paper-card transition-colors"
          >
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" className="h-4 w-4 shrink-0">
              <path strokeLinecap="round" strokeLinejoin="round" d="M3 16.5v2.25A2.25 2.25 0 005.25 21h13.5A2.25 2.25 0 0021 18.75V16.5M16.5 12L12 16.5m0 0L7.5 12m4.5 4.5V3" />
            </svg>
            <span>Exportar ZIP</span>
          </a>

          {/* Botão de sync incremental para iCloud */}
          <button
            type="button"
            onClick={() => void handleBackup()}
            disabled={!backupConfigured || backupState === "running"}
            title={
              !backupConfigured
                ? "Configure HYPO_BACKUP_DIR no .env"
                : backupState === "error"
                  ? `Erro: ${backupError}`
                  : backupState === "ok"
                    ? `Sincronizado às ${lastBackup}`
                    : lastBackup
                      ? `Última sync: ${lastBackup}`
                      : "Sincronizar backup para iCloud"
            }
            className={`flex h-7 w-7 shrink-0 items-center justify-center rounded transition-colors ${
              !backupConfigured
                ? "cursor-not-allowed text-paper-light"
                : backupState === "ok"
                  ? "text-green-500 hover:bg-paper-tag"
                  : backupState === "error"
                    ? "text-red-500 hover:bg-paper-tag"
                    : "text-paper-mid hover:bg-paper-tag hover:text-paper-ink"
            }`}
          >
            {backupState === "running" ? (
              <svg className="h-4 w-4 animate-spin" viewBox="0 0 24 24" fill="none">
                <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="3" />
                <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z" />
              </svg>
            ) : backupState === "ok" ? (
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" className="h-4 w-4">
                <path strokeLinecap="round" strokeLinejoin="round" d="M4.5 12.75l6 6 9-13.5" />
              </svg>
            ) : backupState === "error" ? (
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" className="h-4 w-4">
                <path strokeLinecap="round" strokeLinejoin="round" d="M12 9v3.75m9-.75a9 9 0 11-18 0 9 9 0 0118 0zm-9 3.75h.008v.008H12v-.008z" />
              </svg>
            ) : (
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" className="h-4 w-4">
                <path strokeLinecap="round" strokeLinejoin="round" d="M16.023 9.348h4.992v-.001M2.985 19.644v-4.992m0 0h4.992m-4.993 0 3.181 3.183a8.25 8.25 0 0 0 13.803-3.7M4.031 9.865a8.25 8.25 0 0 1 13.803-3.7l3.181 3.182m0-4.991v4.99" />
              </svg>
            )}
          </button>
        </div>
      </div>
    </aside>
  );
}
