import { useEffect, useRef, useState } from "react";
import { api, type FolderOut, type Item } from "../lib/api";
import { NoteEditor } from "../components/NoteEditor";

interface Props {
  itemId: string;
  initialVideoTime?: number;
  onClose: () => void;
  onChanged: () => void;
  onDeleted: () => void;
  onNavigate?: (id: string) => void;
}

export function DetailModal({ itemId, initialVideoTime, onClose, onChanged, onDeleted, onNavigate }: Props) {
  const [item, setItem] = useState<Item | null>(null);
  const [title, setTitle] = useState("");
  const [note, setNote] = useState("");
  const [tags, setTags] = useState("");
  const [dirty, setDirty] = useState(false);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [description, setDescription] = useState("");
  const [summarizing, setSummarizing] = useState(false);
  const [itemFolders, setItemFolders] = useState<{ id: string; name: string }[]>([]);
  const [allFolders, setAllFolders] = useState<FolderOut[]>([]);
  const [folderPickerOpen, setFolderPickerOpen] = useState(false);
  const folderPickerRef = useRef<HTMLDivElement>(null);
  const [chatMode, setChatMode] = useState(false);
  const [chatMessages, setChatMessages] = useState<{ role: "user" | "assistant"; content: string }[]>([]);
  const [chatInput, setChatInput] = useState("");
  const [chatBusy, setChatBusy] = useState(false);
  const [streamingMsg, setStreamingMsg] = useState("");
  const detailVideoRef = useRef<HTMLVideoElement>(null);
  const videoTimeApplied = useRef(false);
  const messagesEndRef = useRef<HTMLDivElement>(null);

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
        if (it.meta_json) {
          try {
            const meta = JSON.parse(it.meta_json) as { chat_history?: { role: "user" | "assistant"; content: string }[]; summary?: string };
            if (meta.summary) setDescription(meta.summary);
            if (meta.chat_history?.length) {
              setChatMessages(meta.chat_history);
              setChatMode(true);
            }
          } catch { /* ignora meta_json malformado */ }
        }
      })
      .catch((e) => !off && setErr(String(e)));
    api.getItemFolders(itemId).then((f) => { if (!off) setItemFolders(f); }).catch(() => {});
    api.listFolders().then((f) => { if (!off) setAllFolders(f); }).catch(() => {});
    return () => { off = true; };
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
          if (updated.meta_json) {
            try {
              const meta = JSON.parse(updated.meta_json) as { summary?: string };
              setDescription(meta.summary || "");
            } catch {}
          }
        }
      } catch {
        // silencia — próximo tick tenta de novo
      }
    }, 5000);
    return () => clearInterval(id);
  }, [item?.download_status, item?.meta_json, itemId, dirty]);




  async function save() {
    if (!item) return;
    setBusy(true);
    try {
      await api.patchItem(item.id, {
        title: title || null,
        note: note || null,
        summary: description || null,
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
    setDescription("");
    setErr(null);
    let result = "";
    try {
      await api.summarizeStream(item.id, (chunk) => {
        result += chunk;
        setDescription(result);
      });
      if (result.startsWith("[Erro")) {
        setErr(result.replace(/^\[Erro[: ]*/, "Erro: ").replace(/\]$/, ""));
        setDescription("");
      } else {
        setDirty(true);
      }
    } catch (e) {
      setErr(String(e));
      setDescription("");
    } finally {
      setSummarizing(false);
    }
  }

  useEffect(() => {
    messagesEndRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [chatMessages, streamingMsg]);

  useEffect(() => {
    if (!folderPickerOpen) return;
    function onDown(e: MouseEvent) {
      if (folderPickerRef.current && !folderPickerRef.current.contains(e.target as Node))
        setFolderPickerOpen(false);
    }
    document.addEventListener("mousedown", onDown);
    return () => document.removeEventListener("mousedown", onDown);
  }, [folderPickerOpen]);

  async function addToFolder(folderId: string) {
    if (!item) return;
    try {
      await api.addItemsToFolder(folderId, [item.id]);
      setItemFolders(await api.getItemFolders(item.id));
    } catch {}
    setFolderPickerOpen(false);
  }

  async function removeFromFolder(folderId: string) {
    if (!item) return;
    try {
      await api.removeItemFromFolder(folderId, item.id);
      setItemFolders((prev) => prev.filter((f) => f.id !== folderId));
    } catch {}
  }

  async function sendChat() {
    const text = chatInput.trim();
    if (!text || chatBusy || !item) return;
    const newMessages = [...chatMessages, { role: "user" as const, content: text }];
    setChatMessages(newMessages);
    setChatInput("");
    setChatBusy(true);
    setStreamingMsg("");
    try {
      let response = "";
      await api.chatStream(item.id, newMessages, (chunk) => {
        response += chunk;
        setStreamingMsg(response);
      });
      setChatMessages([...newMessages, { role: "assistant" as const, content: response }]);
      setStreamingMsg("");
    } catch (e) {
      setChatMessages([...newMessages, { role: "assistant" as const, content: `[Erro: ${e}]` }]);
      setStreamingMsg("");
    } finally {
      setChatBusy(false);
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

  const thumbnailPath: string | null = (() => {
    if (!item.meta_json) return null;
    try { return (JSON.parse(item.meta_json) as { thumbnail_path?: string }).thumbnail_path ?? null; }
    catch { return null; }
  })();

  const hasEnoughContent = (item?.body_text?.length ?? 0) >= 300;

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
              poster={thumbnailPath ? api.assetUrl(thumbnailPath) : undefined}
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
            <div className="flex items-center gap-2">
              {chatMode && chatMessages.length > 0 && (
                <button
                  type="button"
                  title="Limpar conversa"
                  onClick={async () => {
                    if (!confirm("Limpar todo o histórico desta conversa?")) return;
                    try { await api.clearChatHistory(item.id); } catch {}
                    setChatMessages([]);
                  }}
                  className="text-xs text-paper-mid hover:text-red-500"
                >
                  limpar
                </button>
              )}
              {hasEnoughContent && (
                <button
                  type="button"
                  title={chatMode ? "Voltar às notas" : "Conversar com este conteúdo"}
                  onClick={() => setChatMode((v) => !v)}
                  className={`rounded-md p-1 transition-colors ${
                    chatMode
                      ? "bg-paper-accent/15 text-paper-accent"
                      : "text-paper-mid hover:text-paper-ink"
                  }`}
                >
                  <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="h-4 w-4">
                    <path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z" />
                  </svg>
                </button>
              )}
              <button
                type="button"
                onClick={onClose}
                className="text-paper-mid hover:text-paper-ink"
              >
                ×
              </button>
            </div>
          </div>

          {chatMode ? (
            <>
              <div className="flex-1 overflow-y-auto p-4 space-y-3">
                {chatMessages.length === 0 && !chatBusy && (
                  <div className="mt-10 text-center text-xs text-paper-mid">
                    Faça uma pergunta sobre este conteúdo
                  </div>
                )}
                {chatMessages.map((msg, i) => (
                  <div key={i} className={`flex ${msg.role === "user" ? "justify-end" : "justify-start"}`}>
                    <div className={`max-w-[85%] rounded-xl px-3 py-2 text-sm leading-relaxed ${
                      msg.role === "user"
                        ? "rounded-br-sm bg-paper-accent text-paper-card"
                        : msg.content.startsWith("[Erro")
                          ? "rounded-bl-sm bg-amber-50 text-amber-700"
                          : "rounded-bl-sm bg-paper-tag text-paper-ink"
                    }`}>
                      {msg.content}
                    </div>
                  </div>
                ))}
                {chatBusy && (
                  <div className="flex justify-start">
                    <div className="max-w-[85%] rounded-xl rounded-bl-sm bg-paper-tag px-3 py-2 text-sm leading-relaxed text-paper-ink">
                      {streamingMsg || <span className="text-paper-mid">...</span>}
                      {streamingMsg && <span className="ml-0.5 animate-pulse">▌</span>}
                    </div>
                  </div>
                )}
                <div ref={messagesEndRef} />
              </div>
              <div className="border-t border-paper-border p-3">
                <div className="flex gap-2">
                  <input
                    value={chatInput}
                    onChange={(e) => setChatInput(e.target.value)}
                    onKeyDown={(e) => { if (e.key === "Enter" && !e.shiftKey) { e.preventDefault(); sendChat(); } }}
                    placeholder="Pergunte sobre este conteúdo..."
                    disabled={chatBusy}
                    className="flex-1 rounded-md border border-paper-border bg-paper-bg px-3 py-2 text-sm focus:border-paper-accent focus:outline-none disabled:opacity-50"
                  />
                  <button
                    type="button"
                    onClick={sendChat}
                    disabled={chatBusy || !chatInput.trim()}
                    className="rounded-md bg-paper-accent px-3 py-2 text-sm font-medium text-paper-card hover:opacity-90 disabled:opacity-50"
                  >
                    Enviar
                  </button>
                </div>
              </div>
            </>
          ) : (
          <div className="flex-1 space-y-4 overflow-y-auto p-5">

            {/* Título */}
            <label className="block">
              <div className="mb-1 text-xs font-medium uppercase tracking-wider text-paper-light">
                Título
              </div>
              <input
                value={title}
                onChange={(e) => { setTitle(e.target.value); setDirty(true); }}
                className="w-full rounded-md border border-paper-border bg-paper-bg px-3 py-2 text-sm focus:border-paper-accent focus:outline-none"
              />
            </label>

            {/* Descrição (gerada por IA ou escrita pelo usuário) */}
            <div>
              <div className="mb-1 flex items-center justify-between">
                <span className="text-xs font-medium uppercase tracking-wider text-paper-light">Descrição</span>
                {description && !summarizing && (
                  <button
                    type="button"
                    onClick={() => { setDescription(""); setDirty(true); }}
                    className="text-xs text-paper-mid hover:text-paper-ink"
                  >
                    × limpar
                  </button>
                )}
              </div>
              <textarea
                value={description}
                onChange={(e) => { if (!summarizing) { setDescription(e.target.value); setDirty(true); } }}
                placeholder={summarizing ? "" : "Adicione uma descrição..."}
                rows={4}
                className={`w-full resize-none rounded-md border border-paper-border bg-paper-bg px-3 py-2 text-sm focus:border-paper-accent focus:outline-none ${summarizing ? "opacity-60" : ""}`}
              />
              {summarizing && (
                <div className="mt-1 flex items-center gap-1 text-xs text-paper-mid">
                  <span className="animate-pulse">▌</span> Gerando descrição...
                </div>
              )}
              {!description && !summarizing && (item.body_text || item.title) && (
                <button
                  type="button"
                  onClick={handleSummarize}
                  className="mt-1 text-xs text-paper-accent hover:underline"
                >
                  Gerar com IA
                </button>
              )}
            </div>

            {/* Etiquetas */}
            <label className="block">
              <div className="mb-1 text-xs font-medium uppercase tracking-wider text-paper-light">
                Etiquetas
              </div>
              <input
                value={tags}
                onChange={(e) => { setTags(e.target.value); setDirty(true); }}
                placeholder="separadas por vírgula"
                className="w-full rounded-md border border-paper-border bg-paper-bg px-3 py-2 text-sm focus:border-paper-accent focus:outline-none"
              />
            </label>

            {/* Nota pessoal */}
            <label className="block">
              <div className="mb-1 text-xs font-medium uppercase tracking-wider text-paper-light">
                Nota pessoal
              </div>
              <NoteEditor
                value={note}
                onChange={(val) => { setNote(val); setDirty(true); }}
                knownLinks={[...(item.links || []), ...(item.backlinks || [])]}
                onNavigate={onNavigate}
              />
            </label>

            {/* Fonte */}
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

            {/* Pastas */}
            <div>
              <div className="mb-1 flex items-center justify-between">
                <span className="text-xs font-medium uppercase tracking-wider text-paper-light">Pastas</span>
                <div className="relative" ref={folderPickerRef}>
                  <button
                    type="button"
                    onClick={() => setFolderPickerOpen((v) => !v)}
                    title="Adicionar à pasta"
                    className="rounded p-0.5 text-paper-light hover:bg-paper-bg hover:text-paper-mid"
                  >
                    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" className="h-3.5 w-3.5">
                      <path strokeLinecap="round" strokeLinejoin="round" d="M12 4.5v15m7.5-7.5h-15" />
                    </svg>
                  </button>
                  {folderPickerOpen && (
                    <div className="absolute right-0 top-full z-10 mt-1 w-48 rounded-lg border border-paper-border bg-paper-card shadow-xl">
                      {allFolders.filter((f) => !itemFolders.some((fi) => fi.id === f.id)).length > 0 ? (
                        allFolders
                          .filter((f) => !itemFolders.some((fi) => fi.id === f.id))
                          .map((f) => (
                            <button
                              key={f.id}
                              type="button"
                              onClick={() => void addToFolder(f.id)}
                              className="flex w-full items-center gap-2 px-3 py-2 text-sm text-paper-ink hover:bg-paper-bg"
                            >
                              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" className="h-4 w-4 shrink-0 text-paper-mid">
                                <path strokeLinecap="round" strokeLinejoin="round" d="M2.25 12.75V12A2.25 2.25 0 014.5 9.75h15A2.25 2.25 0 0121.75 12v.75m-8.69-6.44l-2.12-2.12a1.5 1.5 0 00-1.061-.44H4.5A2.25 2.25 0 002.25 6v12a2.25 2.25 0 002.25 2.25h15A2.25 2.25 0 0021.75 18V9a2.25 2.25 0 00-2.25-2.25h-5.379a1.5 1.5 0 01-1.06-.44z" />
                              </svg>
                              <span className="truncate">{f.name}</span>
                            </button>
                          ))
                      ) : (
                        <div className="px-3 py-2 text-xs text-paper-mid">Nenhuma pasta disponível</div>
                      )}
                    </div>
                  )}
                </div>
              </div>
              {itemFolders.length > 0 ? (
                <div className="flex flex-wrap gap-1.5">
                  {itemFolders.map((f) => (
                    <span
                      key={f.id}
                      className="flex items-center gap-1 rounded-full border border-paper-border bg-paper-tag px-2 py-0.5 text-xs text-paper-mid"
                    >
                      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" className="h-3 w-3 shrink-0">
                        <path strokeLinecap="round" strokeLinejoin="round" d="M2.25 12.75V12A2.25 2.25 0 014.5 9.75h15A2.25 2.25 0 0121.75 12v.75m-8.69-6.44l-2.12-2.12a1.5 1.5 0 00-1.061-.44H4.5A2.25 2.25 0 002.25 6v12a2.25 2.25 0 002.25 2.25h15A2.25 2.25 0 0021.75 18V9a2.25 2.25 0 00-2.25-2.25h-5.379a1.5 1.5 0 01-1.06-.44z" />
                      </svg>
                      {f.name}
                      <button
                        type="button"
                        onClick={() => void removeFromFolder(f.id)}
                        className="ml-0.5 rounded-full hover:text-red-500"
                        title="Remover da pasta"
                      >
                        ×
                      </button>
                    </span>
                  ))}
                </div>
              ) : (
                <div className="text-xs text-paper-light">Nenhuma pasta</div>
              )}
            </div>

            {/* Texto do tweet (mantido — é conteúdo explícito do usuário, não dado interno) */}
            {item.kind === "tweet" && item.body_text && (
              <div>
                <div className="mb-1 text-xs font-medium uppercase tracking-wider text-paper-light">
                  Texto do tweet
                </div>
                <p className="text-sm leading-relaxed text-paper-ink">{item.body_text}</p>
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
          )}

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
