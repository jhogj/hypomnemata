import { useEffect, useRef, useState } from "react";
import { api, type Item } from "../lib/api";

interface Props {
  itemId: string;
  initialVideoTime?: number;
  onClose: () => void;
  onChanged: () => void;
  onDeleted: () => void;
}

export function DetailModal({ itemId, initialVideoTime, onClose, onChanged, onDeleted }: Props) {
  const [item, setItem] = useState<Item | null>(null);
  const [title, setTitle] = useState("");
  const [note, setNote] = useState("");
  const [tags, setTags] = useState("");
  const [dirty, setDirty] = useState(false);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [ocrOpen, setOcrOpen] = useState(false);
  const [subOpen, setSubOpen] = useState(false);
  const [summarizing, setSummarizing] = useState(false);
  const [summaryText, setSummaryText] = useState("");
  const [autotagging, setAutotagging] = useState(false);
  const [suggestedTags, setSuggestedTags] = useState<string[]>([]);
  const ocrRef = useRef<HTMLDivElement>(null);
  const subRef = useRef<HTMLDivElement>(null);
  const detailVideoRef = useRef<HTMLVideoElement>(null);
  const videoTimeApplied = useRef(false);

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

  // Polling enquanto download ou IA estiver em andamento.
  useEffect(() => {
    const aiPending = (() => {
      if (!item?.meta_json) return false;
      try { return (JSON.parse(item.meta_json) as { ai_status?: string }).ai_status === "pending"; }
      catch { return false; }
    })();
    if (item?.download_status !== "pending" && !aiPending) return;
    const id = setInterval(async () => {
      try {
        const updated = await api.getItem(itemId);
        setItem(updated);
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
  }, [item?.download_status, item?.meta_json, itemId, dirty]);

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

  useEffect(() => {
    if (!subOpen) return;
    function handleClick(e: MouseEvent) {
      if (subRef.current && !subRef.current.contains(e.target as Node)) {
        setSubOpen(false);
      }
    }
    document.addEventListener("mousedown", handleClick);
    return () => document.removeEventListener("mousedown", handleClick);
  }, [subOpen]);

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

  async function handleSummarize() {
    if (!item) return;
    setSummarizing(true);
    setSummaryText("");
    setErr(null);
    try {
      await api.summarizeStream(item.id, (chunk) =>
        setSummaryText((prev) => prev + chunk),
      );
      const updated = await api.getItem(item.id);
      setItem(updated);
    } catch (e) {
      setErr(String(e));
    } finally {
      setSummarizing(false);
    }
  }

  async function handleAutotag() {
    if (!item) return;
    setAutotagging(true);
    setSuggestedTags([]);
    setErr(null);
    try {
      setSuggestedTags(await api.autotagItem(item.id));
    } catch (e) {
      setErr(String(e));
    } finally {
      setAutotagging(false);
    }
  }

  function addSuggestedTag(tag: string) {
    const current = tags.split(",").map((t) => t.trim()).filter(Boolean);
    if (!current.includes(tag)) {
      setTags([...current, tag].join(", "));
      setDirty(true);
    }
    setSuggestedTags((prev) => prev.filter((t) => t !== tag));
  }

  function addAllSuggestedTags() {
    const current = tags.split(",").map((t) => t.trim()).filter(Boolean);
    const toAdd = suggestedTags.filter((t) => !current.includes(t));
    if (toAdd.length) { setTags([...current, ...toAdd].join(", ")); setDirty(true); }
    setSuggestedTags([]);
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
  const isPdf =
    item.asset_path && /\.pdf$/i.test(item.asset_path);

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

  // Article metadata from meta_json.
  const articleMeta: { author?: string; pub_date?: string; sitename?: string; description?: string } | null = (() => {
    if (item.kind !== "article" || !item.meta_json) return null;
    try {
      return JSON.parse(item.meta_json) as { author?: string; pub_date?: string; sitename?: string; description?: string };
    } catch {
      return null;
    }
  })();

  const isArticleReady = item.kind === "article" && item.body_text && item.download_status === "done";

  const existingSummary: string | null = (() => {
    if (!item.meta_json) return null;
    try { return (JSON.parse(item.meta_json) as { summary?: string }).summary ?? null; }
    catch { return null; }
  })();

  const isAiPending: boolean = (() => {
    if (!item.meta_json) return false;
    try { return (JSON.parse(item.meta_json) as { ai_status?: string }).ai_status === "pending"; }
    catch { return false; }
  })();

  function downloadLabel(status: string | null, _kind: string): string | null {
    if (!status || status === "done") return null;
    if (status === "pending") {
      if (!item?.source_url) return "Processando upload...";
      return _kind === "article" ? "Extraindo artigo..." : "Baixando...";
    }
    if (status === "error:missing_dep") return _kind === "article" ? "trafilatura não instalado" : "yt-dlp não instalado";
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
          {isArticleReady ? (
            /* ── Article reader view ─────────────────────────────── */
            <article className="mx-auto max-w-prose space-y-4">
              {isImage && (
                <img
                  src={api.assetUrl(item.asset_path!)}
                  alt={item.title || ""}
                  className="w-full rounded-lg object-cover"
                />
              )}
              {item.title && (
                <h1 className="text-xl font-bold leading-snug text-paper-ink">
                  {item.title}
                </h1>
              )}
              {articleMeta && (articleMeta.author || articleMeta.pub_date || articleMeta.sitename) && (
                <div className="flex flex-wrap gap-2 text-xs text-paper-mid">
                  {articleMeta.sitename && <span className="font-medium">{articleMeta.sitename}</span>}
                  {articleMeta.author && <span>· {articleMeta.author}</span>}
                  {articleMeta.pub_date && <span>· {articleMeta.pub_date}</span>}
                </div>
              )}
              <div className="border-t border-paper-border" />
              <div className="prose-sm text-sm leading-relaxed text-paper-ink">
                {item.body_text!.split("\n").filter(l => l.trim()).map((para, i) => (
                  <p key={i} className="mb-4">
                    {para}
                  </p>
                ))}
              </div>
            </article>
          ) : mediaPaths ? (
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
              ref={detailVideoRef}
              src={api.assetUrl(item.asset_path!)}
              controls
              autoPlay={initialVideoTime != null && initialVideoTime > 0}
              onLoadedMetadata={() => {
                if (
                  !videoTimeApplied.current &&
                  initialVideoTime != null &&
                  initialVideoTime > 0 &&
                  detailVideoRef.current
                ) {
                  detailVideoRef.current.currentTime = initialVideoTime;
                  videoTimeApplied.current = true;
                }
              }}
              className="mx-auto max-h-full w-full"
            />
          ) : isPdf ? (
            <object
              data={api.assetUrl(item.asset_path!)}
              type="application/pdf"
              className="h-full w-full rounded"
            >
              <div className="flex h-full items-center justify-center text-sm text-paper-mid">
                Seu navegador não suporta visualização de PDFs.
                <a
                  href={api.assetUrl(item.asset_path!)}
                  target="_blank"
                  rel="noreferrer"
                  className="ml-1 text-paper-accent underline"
                >
                  Baixar arquivo
                </a>
              </div>
            </object>
          ) : item.download_status === "pending" ? (
            <div className="flex h-full items-center justify-center text-sm text-paper-mid">
              {item.source_url ? "Baixando mídia..." : "Processando upload..."}
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

            {(item.body_text || item.title) && (
              <div className="space-y-2 border-t border-paper-border pt-3">
                <div className="flex items-center justify-between">
                  <span className="text-xs font-medium uppercase tracking-wider text-paper-light">IA</span>
                  <div className="flex gap-1.5">
                    <button
                      type="button"
                      onClick={handleSummarize}
                      disabled={summarizing || autotagging || isAiPending}
                      className="rounded-md border border-paper-border px-2.5 py-1 text-xs text-paper-mid hover:bg-paper-bg disabled:opacity-40"
                    >
                      {summarizing ? "Resumindo..." : isAiPending ? "IA processando..." : existingSummary ? "Refazer resumo" : "Resumir"}
                    </button>
                    <button
                      type="button"
                      onClick={handleAutotag}
                      disabled={summarizing || autotagging}
                      className="rounded-md border border-paper-border px-2.5 py-1 text-xs text-paper-mid hover:bg-paper-bg disabled:opacity-40"
                    >
                      {autotagging ? "Sugerindo..." : "Sugerir tags"}
                    </button>
                  </div>
                </div>

                {isAiPending && !summaryText && (
                  <div className="flex items-center gap-2 rounded-md border border-paper-border bg-paper-tag px-3 py-2 text-xs text-paper-mid">
                    <span className="animate-pulse">▌</span>
                    Gerando resumo com IA...
                  </div>
                )}

                {(summaryText || existingSummary) && (() => {
                  const text = summaryText || existingSummary!;
                  if (!summarizing && text.startsWith("[Erro")) {
                    return (
                      <div className="rounded-md bg-amber-50 px-3 py-2 text-xs text-amber-700">
                        {text.replace(/^\[Erro[: ]*/, "Erro: ").replace(/\]$/, "")}
                      </div>
                    );
                  }
                  return (
                    <div className={`rounded-md border border-paper-border p-3 text-xs leading-relaxed text-paper-ink ${summarizing ? "bg-paper-tag" : "bg-paper-bg"}`}>
                      {text}
                      {summarizing && <span className="ml-0.5 animate-pulse">▌</span>}
                    </div>
                  );
                })()}

                {suggestedTags.length > 0 && (
                  <div className="space-y-1.5">
                    <div className="flex flex-wrap gap-1">
                      {suggestedTags.map((tag) => (
                        <button
                          key={tag}
                          type="button"
                          onClick={() => addSuggestedTag(tag)}
                          className="rounded-full border border-paper-accent/30 bg-paper-accent/10 px-2 py-0.5 text-xs text-paper-accent hover:bg-paper-accent/20"
                        >
                          + {tag}
                        </button>
                      ))}
                    </div>
                    <button
                      type="button"
                      onClick={addAllSuggestedTags}
                      className="text-xs text-paper-accent hover:underline"
                    >
                      Adicionar todas
                    </button>
                  </div>
                )}
              </div>
            )}

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

            {item.kind === "video" && item.body_text && item.download_status === "done" && (() => {
              const meta = item.meta_json ? (() => { try { return JSON.parse(item.meta_json!); } catch { return {}; } })() : {};
              const label = meta.subtitle_lang
                ? `Legenda (${meta.subtitle_lang})`
                : "Descrição do vídeo";
              return (
                <div ref={subRef}>
                  <button
                    type="button"
                    onClick={() => setSubOpen((v) => !v)}
                    className="flex w-full items-center justify-between text-xs font-medium uppercase tracking-wider text-paper-light hover:text-paper-mid"
                  >
                    <span>{label}</span>
                    <span>{subOpen ? "▾" : "▸"}</span>
                  </button>
                  {subOpen && (
                    <div className="mt-2 max-h-48 overflow-y-auto rounded-md border border-paper-border bg-paper-tag p-3 text-xs leading-relaxed text-paper-ink">
                      {item.body_text}
                    </div>
                  )}
                </div>
              );
            })()}

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
