import { useEffect, useRef, useState } from "react";
import { api, type Kind } from "../lib/api";

interface Props {
  onClose: () => void;
  onSaved: () => void;
}

type Tab = "url" | "file" | "text";

export function CaptureModal({ onClose, onSaved }: Props) {
  const [tab, setTab] = useState<Tab>("url");
  const [url, setUrl] = useState("");
  const [text, setText] = useState("");
  const [title, setTitle] = useState("");
  const [note, setNote] = useState("");
  const [tags, setTags] = useState("");
  const [file, setFile] = useState<File | null>(null);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const firstFocus = useRef<HTMLInputElement>(null);

  useEffect(() => {
    firstFocus.current?.focus();
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") onClose();
      if ((e.metaKey || e.ctrlKey) && e.key === "Enter") {
        e.preventDefault();
        void save();
      }
    };
    document.addEventListener("keydown", onKey);
    return () => document.removeEventListener("keydown", onKey);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  function inferKind(): Kind {
    if (tab === "file" && file) {
      const n = file.name.toLowerCase();
      if (/\.(png|jpe?g|gif|webp|bmp|svg)$/.test(n)) return "image";
      if (/\.(mp4|mov|webm|mkv|avi)$/.test(n)) return "video";
      if (/\.pdf$/.test(n)) return "pdf";
      return "image";
    }
    if (tab === "url" && url) {
      if (/x\.com|twitter\.com/.test(url)) return "tweet";
      if (
        /youtube\.com\/(?:watch|shorts|live|embed)/.test(url) ||
        /youtu\.be\//.test(url) ||
        /vimeo\.com\/\d/.test(url)
      )
        return "video";
      return "bookmark";
    }
    return "note";
  }

  async function save() {
    setErr(null);
    if (tab === "url" && !url) return setErr("informe uma URL");
    if (tab === "file" && !file) return setErr("selecione um arquivo");
    if (tab === "text" && !text.trim() && !title.trim())
      return setErr("informe título ou texto");

    setBusy(true);
    try {
      const kind = inferKind();
      await api.createCapture({
        kind,
        source_url: tab === "url" ? url : undefined,
        title: title || undefined,
        note: note || undefined,
        body_text: tab === "text" ? text : undefined,
        tags: tags
          .split(",")
          .map((t) => t.trim())
          .filter(Boolean),
        file: tab === "file" && file ? file : undefined,
      });
      onSaved();
    } catch (e) {
      setErr(String(e));
    } finally {
      setBusy(false);
    }
  }

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4"
      onClick={onClose}
    >
      <div
        className="w-full max-w-xl rounded-xl bg-paper-card shadow-2xl"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-center justify-between border-b border-paper-border px-5 py-4">
          <div className="text-lg font-semibold text-paper-ink">Nova captura</div>
          <button
            type="button"
            onClick={onClose}
            className="text-paper-mid hover:text-paper-ink"
            aria-label="Fechar"
          >
            ×
          </button>
        </div>

        <div className="px-5 pt-4">
          <div className="mb-3 flex gap-2">
            {(["url", "file", "text"] as const).map((t) => (
              <button
                key={t}
                type="button"
                onClick={() => setTab(t)}
                className={`rounded-md border px-3 py-1 text-sm ${
                  tab === t
                    ? "border-paper-accent bg-paper-tag text-paper-ink"
                    : "border-paper-border text-paper-mid hover:bg-paper-bg"
                }`}
              >
                {t === "url" ? "URL" : t === "file" ? "Arquivo" : "Texto"}
              </button>
            ))}
          </div>

          {tab === "url" && (
            <input
              ref={firstFocus}
              type="url"
              value={url}
              onChange={(e) => setUrl(e.target.value)}
              placeholder="https://..."
              className="mb-3 w-full rounded-md border border-paper-border bg-paper-bg px-3 py-2 text-sm focus:border-paper-accent focus:outline-none"
            />
          )}

          {tab === "file" && (
            <label className="mb-3 flex h-28 cursor-pointer items-center justify-center rounded-md border border-dashed border-paper-border bg-paper-bg text-sm text-paper-mid hover:bg-paper-tag">
              {file ? file.name : "arraste um arquivo ou clique para escolher"}
              <input
                type="file"
                className="hidden"
                onChange={(e) => setFile(e.target.files?.[0] ?? null)}
              />
            </label>
          )}

          {tab === "text" && (
            <textarea
              ref={firstFocus as unknown as React.RefObject<HTMLTextAreaElement>}
              value={text}
              onChange={(e) => setText(e.target.value)}
              placeholder="Cole ou digite o texto..."
              rows={5}
              className="mb-3 w-full rounded-md border border-paper-border bg-paper-bg px-3 py-2 text-sm focus:border-paper-accent focus:outline-none"
            />
          )}

          <input
            type="text"
            value={title}
            onChange={(e) => setTitle(e.target.value)}
            placeholder="título (opcional)"
            className="mb-2 w-full rounded-md border border-paper-border bg-paper-bg px-3 py-2 text-sm focus:border-paper-accent focus:outline-none"
          />

          <input
            type="text"
            value={note}
            onChange={(e) => setNote(e.target.value)}
            placeholder="nota pessoal (opcional)"
            className="mb-2 w-full rounded-md border border-paper-border bg-paper-bg px-3 py-2 text-sm focus:border-paper-accent focus:outline-none"
          />

          <input
            type="text"
            value={tags}
            onChange={(e) => setTags(e.target.value)}
            placeholder="etiquetas (separadas por vírgula)"
            className="mb-3 w-full rounded-md border border-paper-border bg-paper-bg px-3 py-2 text-sm focus:border-paper-accent focus:outline-none"
          />

          {err && (
            <div className="mb-3 rounded-md bg-red-50 px-3 py-2 text-sm text-red-700">
              {err}
            </div>
          )}
        </div>

        <div className="flex items-center justify-between border-t border-paper-border px-5 py-3">
          <div className="text-xs text-paper-light">⌘↵ salva · Esc fecha</div>
          <div className="flex gap-2">
            <button
              type="button"
              onClick={onClose}
              className="rounded-md border border-paper-border px-3 py-1.5 text-sm text-paper-mid hover:bg-paper-bg"
            >
              Cancelar
            </button>
            <button
              type="button"
              onClick={save}
              disabled={busy}
              className="rounded-md bg-paper-accent px-4 py-1.5 text-sm font-medium text-paper-card hover:opacity-90 disabled:opacity-50"
            >
              {busy ? "Salvando..." : "Salvar"}
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}
