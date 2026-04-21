export const DEFAULT_API = "http://127.0.0.1:8787";

export async function getApiBase(): Promise<string> {
  const { api_base } = await chrome.storage.local.get("api_base");
  return (api_base as string) || DEFAULT_API;
}

export async function setApiBase(base: string): Promise<void> {
  await chrome.storage.local.set({ api_base: base });
}

export type Kind =
  | "image"
  | "article"
  | "video"
  | "tweet"
  | "bookmark"
  | "note"
  | "pdf";

export interface CapturePayload {
  kind: Kind;
  source_url?: string;
  title?: string;
  note?: string;
  body_text?: string;
  tags?: string[];
  meta_json?: string;
  /** base64-encoded PNG data (no data: prefix) */
  screenshot_base64?: string;
  screenshot_filename?: string;
}

export async function postCapture(payload: CapturePayload): Promise<{ id: string }> {
  const base = await getApiBase();
  const fd = new FormData();
  fd.set("kind", payload.kind);
  if (payload.source_url) fd.set("source_url", payload.source_url);
  if (payload.title) fd.set("title", payload.title);
  if (payload.note) fd.set("note", payload.note);
  if (payload.body_text) fd.set("body_text", payload.body_text);
  if (payload.tags?.length) fd.set("tags", payload.tags.join(","));
  if (payload.meta_json) fd.set("meta_json", payload.meta_json);
  if (payload.screenshot_base64) {
    const bin = atob(payload.screenshot_base64);
    const bytes = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
    fd.set(
      "file",
      new Blob([bytes], { type: "image/png" }),
      payload.screenshot_filename || "capture.png",
    );
  }
  const r = await fetch(`${base}/captures`, { method: "POST", body: fd });
  if (!r.ok) throw new Error(`HTTP ${r.status}: ${await r.text()}`);
  return r.json();
}

export function detectKind(url: string): Kind {
  if (/\/\/(?:www\.)?x\.com\//.test(url) || /\/\/(?:www\.)?twitter\.com\//.test(url))
    return "tweet";
  // Video platforms suportados pelo yt-dlp (MVP: YouTube e Vimeo)
  if (
    /\/\/(?:www\.)?youtube\.com\/(?:watch|shorts|live|embed)/.test(url) ||
    /\/\/youtu\.be\//.test(url) ||
    /\/\/(?:www\.)?vimeo\.com\/\d/.test(url)
  )
    return "video";
  if (/\.(png|jpe?g|gif|webp|bmp)(\?|$)/i.test(url)) return "image";
  if (/\.(mp4|webm|mov)(\?|$)/i.test(url)) return "video";
  if (/\.pdf(\?|$)/i.test(url)) return "pdf";
  return "bookmark";
}
