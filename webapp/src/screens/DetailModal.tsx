import { useEffect, useRef, useState } from "react";
import { api, type Item } from "../lib/api";

interface Props {
  itemId: string;
  onClose: () => void;
  onChanged: () => void;
  onDeleted: () => void;
}

export function DetailModal({ itemId, onClose, onChanged, onDeleted }: Props) {
  const [item, setItem] = useState<Item | null>(null);
  const [title, setTitle] = useState("");
  const [note, setNote] = useState("");
  const [tags, setTags] = useState("");
  const [dirty, setDirty] = useState(false);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [ocrOpen, setOcrOpen] = useState(false);
  const ocrRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    let off = false;
    api
      .getItem(itemId)
      .then((it) => {
        if (off) return;
        setItem(it);
        setTitle(it.title || "");
        setNote(it.note || "");
        setTags(it.tags.join(", "));
      })
      .catch((e) => !off && setErr(String(e)));
    return () => {
      off = true;
    };
  }, [itemId]);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") onClose();
    };
    document.addEventListener("keydown", onKey);
    return () => document.removeEventListener("keydown", onKey);
  }, [onClose]);

  // Polling enquanto o download está em andamento — atualiza o item a cada 5s.
  useEffect(() => {
    if (item?.download_status !== "pending") return;
    const id = setInterval(async () => {
      try {
        const updated = await api.getItem(itemId);
        setItem(updated);
        // Só sobrescreve campos do formulário se o usuário não editou nada.
        if (!dirty) {
          setTitle(updated.title || "");
          setNote(updated.note || "");
          setTags(updated.tags.join(", "));
        }
      } catch {
        // silencia — próximo tick tenta de novo
      }
    }, 5000);
    return () => clearInterval(id);
  }, [item?.download_status, itemId, dirty]);

  useEffect(() => {
    if (!ocrOpen) return;
    function handleClick(e: MouseEvent) {
      if (ocrRef.current && !ocrRef.current.contains(e.target as Node)) {
        setOcrOpen(false);
      }
    }
    document.addEventListener("mousedown", handleClick);
    return () => document.removeEventListener("mousedown", handleClick);
  }, [ocrOpen]);

  async function save() {
    if (!item) return;
    setBusy(true);
    try {
      await api.patchItem(item.id, {
        title: title || null,
        note: note || null,
        tags: tags
          .split(",")
          .map((t) => t.trim())
          .filter(Boolean),
      });
      setDirty(false);
      onChanged();
    } catch (e) {
      setErr(String(e));
    } finally {
      setBusy(false);
    }
  }

  async function del() {
    if (!item) return;
    if (!confirm("Excluir esta captura?")) return;
    setBusy(true);
    try {
      await api.deleteItem(item.id);
      onDeleted();
    } catch (e) {
      setErr(String(e));
      setBusy(false);
    }
  }

  if (!item)
    return (
      <div
        className="fixed inset-0 z-50 flex items-center justify-center bg-black/50"
        onClick={onClose}
      >
        <div className="rounded bg-paper-card px-4 py-2 text-sm text-paper-mid">
          {err || "carregando..."}
        </div>
      </div>
    );

  const isImage =
    item.asset_path && /\.(png|jpe?g|gif|webp|bmp)$/i.test(item.asset_path);
  const isVideo =
    item.asset_path && /\.(mp4|webm|mkv|mov|m4v)$/i.test(item.asset_path);

  // Multiple images from a tweet gallery are stored as meta_json.media_paths.
  const mediaPaths: string[] | null = (() => {
    if (!item.meta_json) return null;
    try {
      const m = JSON.parse(item.meta_json) as { media_paths?: string[] };
      return Array.isArray(m.media_paths) && m.media_paths.length > 1 ? m.media_paths : null;
    } catch {
      return null;
    }
  })();

  function downloadLabel(status: string | null, _kind: string): string | null {
    if (!status || status === "done") return null;
    if (status === "pending") return "Baixando...";
    if (status === "error:missing_dep") return "yt-dlp não instalado";
    if (status === "error:too_large") return "Mídia acima do limite de tamanho";
    return status.replace("error:", "Erro: ");
  }

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4"
      onClick={onClose}
    >
      <div
        className="grid h-[85vh] w-full max-w-5xl grid-cols-[1.2fr_1fr] overflow-hidden rounded-xl bg-paper-card shadow-2xl"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="overflow-auto border-r border-paper-border bg-paper-bg p-4">
          {mediaPaths ? (
            <div
              className={`grid gap-1 ${
                mediaPaths.length === 3 ? "grid-cols-2 grid-rows-2" : "grid-cols-2"
              }`}
            >
              {mediaPaths.map((p, i) => (
                <img
                  key={p}
                  src={api.assetUrl(p)}
                  alt=""
                  className={`w-full rounded object-cover ${
                    mediaPaths.length === 3 && i === 0 ? "row-span-2 h-full" : "aspect-square"
                  }`}
                />
              ))}
            </div>
          ) : isImage ? (
            <img
              src={api.assetUrl(item.asset_path!)}
              alt={item.title || ""}
              className="mx-auto max-h-full w-auto"
            />
          ) : isVideo ? (
            <video
              src={api.assetUrl(item.asset_path!)}
              controls
              className="mx-auto max-h-full w-full"
            />
          ) : item.download_status === "pending" ? (
            <div className="flex h-full items-center justify-center text-sm text-paper-mid">
              Baixando mídia...
            </div>
          ) : item.asset_path ? (
            <a
              href={api.assetUrl(item.asset_path)}
              target="_blank"
              rel="noreferrer"
              className="text-paper-accent underline"
            >
              abrir asset ({item.asset_path})
            </a>
          ) : item.body_text ? (
            <pre className="whitespace-pre-wrap font-sans text-sm text-paper-ink">
              {item.body_text}
            </pre>
          ) : (
            <div className="text-sm text-paper-mid">sem preview</div>
          )}
        </div>

        <div className="flex flex-col overflow-hidden">
          <div className="flex items-center justify-between border-b border-paper-border px-5 py-4">
            <div className="text-sm text-paper-mid">
              {item.kind} · {new Date(item.captured_at).toLocaleString("pt-BR")}
            </div>
            <button
              type="button"
              onClick={onClose}
              className="text-paper-mid hover:text-paper-ink"
            >
              ×
            </button>
          </div>

          <div className="flex-1 space-y-4 overflow-y-auto p-5">
            {item.source_url && (
              <div>
                <div className="mb-1 text-xs font-medium uppercase tracking-wider text-paper-light">
                  Fonte
                </div>
                <a
                  href={item.source_url}
                  target="_blank"
                  rel="noreferrer"
                  className="block truncate text-sm text-paper-accent hover:underline"
                >
                  {item.source_url}
                </a>
              </div>
            )}

            <label className="block">
              <div className="mb-1 text-xs font-medium uppercase tracking-wider text-paper-light">
                Título
              </div>
              <input
                value={title}
                onChange={(e) => {
                  setTitle(e.target.value);
                  setDirty(true);
                }}
                className="w-full rounded-md border border-paper-border bg-paper-bg px-3 py-2 text-sm focus:border-paper-accent focus:outline-none"
              />
            </label>

            <label className="block">
              <div className="mb-1 text-xs font-medium uppercase tracking-wider text-paper-light">
                Nota pessoal
              </div>
              <textarea
                value={note}
                rows={4}
                onChange={(e) => {
                  setNote(e.target.value);
                  setDirty(true);
                }}
                className="w-full resize-y rounded-md border border-paper-border bg-paper-bg px-3 py-2 text-sm focus:border-paper-accent focus:outline-none"
              />
            </label>

            <label className="block">
              <div className="mb-1 text-xs font-medium uppercase tracking-wider text-paper-light">
                Etiquetas
              </div>
              <input
                value={tags}
                onChange={(e) => {
                  setTags(e.target.value);
                  setDirty(true);
                }}
                placeholder="separadas por vírgula"
                className="w-full rounded-md border border-paper-border bg-paper-bg px-3 py-2 text-sm focus:border-paper-accent focus:outline-none"
              />
            </label>

            {item.kind === "tweet" && item.body_text && (
              <div>
                <div className="mb-1 text-xs font-medium uppercase tracking-wider text-paper-light">
                  Texto do tweet
                </div>
                <p className="text-sm leading-relaxed text-paper-ink">{item.body_text}</p>
              </div>
            )}

            {item.body_text && item.ocr_status === "done" && (
              <div ref={ocrRef}>
                <button
                  type="button"
                  onClick={() => setOcrOpen((v) => !v)}
                  className="flex w-full items-center justify-between text-xs font-medium uppercase tracking-wider text-paper-light hover:text-paper-mid"
                >
                  <span>Texto extraído</span>
                  <span>{ocrOpen ? "▾" : "▸"}</span>
                </button>
                {ocrOpen && (
                  <div className="mt-2 max-h-48 overflow-y-auto rounded-md border border-paper-border bg-paper-tag p-3 text-xs leading-relaxed text-paper-ink">
                    {item.body_text}
                  </div>
                )}
              </div>
            )}

            {downloadLabel(item.download_status, item.kind) && (
              <div className={`rounded-md px-3 py-2 text-xs ${
                item.download_status === "pending"
                  ? "bg-paper-tag text-paper-mid"
                  : "bg-amber-50 text-amber-700"
              }`}>
                {downloadLabel(item.download_status, item.kind)}
              </div>
            )}

            {err && (
              <div className="rounded-md bg-red-50 px-3 py-2 text-sm text-red-700">
                {err}
              </div>
            )}
          </div>

          <div className="flex items-center justify-between border-t border-paper-border px-5 py-3">
            <button
              type="button"
              onClick={del}
              disabled={busy}
              className="rounded-md bg-red-600 px-3 py-1.5 text-sm text-white hover:bg-red-700 disabled:opacity-50"
            >
              Excluir
            </button>
            <div className="flex gap-2">
              {item.source_url && (
                <a
                  href={item.source_url}
                  target="_blank"
                  rel="noreferrer"
                  className="rounded-md border border-paper-border px-3 py-1.5 text-sm text-paper-mid hover:bg-paper-bg"
                >
                  Abrir original
                </a>
              )}
              <button
                type="button"
                onClick={save}
                disabled={!dirty || busy}
                className="rounded-md bg-paper-accent px-4 py-1.5 text-sm font-medium text-paper-card hover:opacity-90 disabled:opacity-50"
              >
                {busy ? "Salvando..." : "Salvar"}
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
