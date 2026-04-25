import { useEffect, useRef, useState } from "react";
import { type FolderOut } from "../lib/api";

interface Props {
  count: number;
  folders: FolderOut[];
  onAddToFolder: (folderId: string) => void;
  onCreateAndAdd: (name: string) => void;
  onDeleteSelected: () => void;
  onCancel: () => void;
}

export function SelectionToolbar({ count, folders, onAddToFolder, onCreateAndAdd, onDeleteSelected, onCancel }: Props) {
  const [folderOpen, setFolderOpen] = useState(false);
  const [creating, setCreating] = useState(false);
  const [newName, setNewName] = useState("");
  const dropRef = useRef<HTMLDivElement>(null);
  const inputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    if (!folderOpen) return;
    function onDown(e: MouseEvent) {
      if (dropRef.current && !dropRef.current.contains(e.target as Node)) setFolderOpen(false);
    }
    document.addEventListener("mousedown", onDown);
    return () => document.removeEventListener("mousedown", onDown);
  }, [folderOpen]);

  useEffect(() => {
    if (creating) inputRef.current?.focus();
  }, [creating]);

  function submitCreate() {
    const name = newName.trim();
    if (!name) return;
    onCreateAndAdd(name);
    setNewName("");
    setCreating(false);
    setFolderOpen(false);
  }

  return (
    <div className="fixed bottom-6 left-1/2 z-40 -translate-x-1/2">
      <div className="flex items-center gap-3 rounded-xl border border-paper-border bg-paper-card px-4 py-3 shadow-2xl">
        <span className="text-sm font-medium text-paper-ink">
          {count} {count === 1 ? "item" : "itens"} selecionado{count === 1 ? "" : "s"}
        </span>

        <div className="h-4 w-px bg-paper-border" />

        {/* Adicionar à pasta */}
        <div className="relative" ref={dropRef}>
          <button
            type="button"
            onClick={() => setFolderOpen((v) => !v)}
            className="flex items-center gap-1.5 rounded-md border border-paper-border px-3 py-1.5 text-sm text-paper-mid hover:bg-paper-bg"
          >
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" className="h-4 w-4">
              <path strokeLinecap="round" strokeLinejoin="round" d="M2.25 12.75V12A2.25 2.25 0 014.5 9.75h15A2.25 2.25 0 0121.75 12v.75m-8.69-6.44l-2.12-2.12a1.5 1.5 0 00-1.061-.44H4.5A2.25 2.25 0 002.25 6v12a2.25 2.25 0 002.25 2.25h15A2.25 2.25 0 0021.75 18V9a2.25 2.25 0 00-2.25-2.25h-5.379a1.5 1.5 0 01-1.06-.44z" />
            </svg>
            Adicionar à pasta
          </button>

          {folderOpen && (
            <div className="absolute bottom-full mb-2 left-0 w-52 rounded-lg border border-paper-border bg-paper-card shadow-xl">
              {folders.length > 0 && (
                <div className="py-1">
                  {folders.map((f) => (
                    <button
                      key={f.id}
                      type="button"
                      onClick={() => { onAddToFolder(f.id); setFolderOpen(false); }}
                      className="flex w-full items-center gap-2 px-3 py-2 text-sm text-paper-ink hover:bg-paper-bg"
                    >
                      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" className="h-4 w-4 shrink-0 text-paper-mid">
                        <path strokeLinecap="round" strokeLinejoin="round" d="M2.25 12.75V12A2.25 2.25 0 014.5 9.75h15A2.25 2.25 0 0121.75 12v.75m-8.69-6.44l-2.12-2.12a1.5 1.5 0 00-1.061-.44H4.5A2.25 2.25 0 002.25 6v12a2.25 2.25 0 002.25 2.25h15A2.25 2.25 0 0021.75 18V9a2.25 2.25 0 00-2.25-2.25h-5.379a1.5 1.5 0 01-1.06-.44z" />
                      </svg>
                      <span className="truncate">{f.name}</span>
                    </button>
                  ))}
                  <div className="my-1 border-t border-paper-border" />
                </div>
              )}
              {creating ? (
                <div className="p-2">
                  <input
                    ref={inputRef}
                    value={newName}
                    onChange={(e) => setNewName(e.target.value)}
                    onKeyDown={(e) => { if (e.key === "Enter") submitCreate(); if (e.key === "Escape") setCreating(false); }}
                    placeholder="Nome da pasta"
                    className="w-full rounded border border-paper-border bg-paper-bg px-2 py-1.5 text-sm focus:border-paper-accent focus:outline-none"
                  />
                  <div className="mt-1.5 flex gap-1.5">
                    <button type="button" onClick={submitCreate} className="flex-1 rounded bg-paper-accent px-2 py-1 text-xs font-medium text-paper-card hover:opacity-90">Criar</button>
                    <button type="button" onClick={() => setCreating(false)} className="flex-1 rounded border border-paper-border px-2 py-1 text-xs text-paper-mid hover:bg-paper-bg">Cancelar</button>
                  </div>
                </div>
              ) : (
                <button
                  type="button"
                  onClick={() => setCreating(true)}
                  className="flex w-full items-center gap-2 px-3 py-2 text-sm text-paper-accent hover:bg-paper-bg"
                >
                  <span className="text-base leading-none">+</span> Nova pasta
                </button>
              )}
            </div>
          )}
        </div>

        {/* Excluir */}
        <button
          type="button"
          onClick={onDeleteSelected}
          className="flex items-center gap-1.5 rounded-md border border-red-200 px-3 py-1.5 text-sm text-red-600 hover:bg-red-50"
        >
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" className="h-4 w-4">
            <path strokeLinecap="round" strokeLinejoin="round" d="M14.74 9l-.346 9m-4.788 0L9.26 9m9.968-3.21c.342.052.682.107 1.022.166m-1.022-.165L18.16 19.673a2.25 2.25 0 01-2.244 2.077H8.084a2.25 2.25 0 01-2.244-2.077L4.772 5.79m14.456 0a48.108 48.108 0 00-3.478-.397m-12 .562c.34-.059.68-.114 1.022-.165m0 0a48.11 48.11 0 013.478-.397m7.5 0v-.916c0-1.18-.91-2.164-2.09-2.201a51.964 51.964 0 00-3.32 0c-1.18.037-2.09 1.022-2.09 2.201v.916m7.5 0a48.667 48.667 0 00-7.5 0" />
          </svg>
          Excluir
        </button>

        <div className="h-4 w-px bg-paper-border" />

        <button
          type="button"
          onClick={onCancel}
          className="text-sm text-paper-mid hover:text-paper-ink"
        >
          Cancelar
        </button>
      </div>
    </div>
  );
}
