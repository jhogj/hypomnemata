export type Kind =
  | "image"
  | "article"
  | "video"
  | "tweet"
  | "bookmark"
  | "note"
  | "pdf";

export interface Item {
  id: string;
  kind: Kind;
  source_url: string | null;
  title: string | null;
  note: string | null;
  body_text: string | null;
  asset_path: string | null;
  meta_json: string | null;
  ocr_status: string | null;
  download_status: string | null;
  captured_at: string;
  created_at: string;
  tags: string[];
}

export interface ItemList {
  items: Item[];
  total: number;
}

export interface TagCount {
  name: string;
  count: number;
}

// Uses Vite's /api proxy in dev (see vite.config.ts).
const API = "/api";

async function j<T>(r: Response): Promise<T> {
  if (!r.ok) {
    let detail: unknown = undefined;
    try {
      detail = await r.json();
    } catch {
      detail = await r.text();
    }
    throw new Error(`HTTP ${r.status}: ${JSON.stringify(detail)}`);
  }
  return r.json() as Promise<T>;
}

export interface StorageInfo {
  total_bytes: number;
}

export const api = {
  async listItems(params: {
    kind?: string;
    tag?: string;
    limit?: number;
    offset?: number;
  } = {}): Promise<ItemList> {
    const q = new URLSearchParams();
    if (params.kind) q.set("kind", params.kind);
    if (params.tag) q.set("tag", params.tag);
    if (params.limit !== undefined) q.set("limit", String(params.limit));
    if (params.offset !== undefined) q.set("offset", String(params.offset));
    return j(await fetch(`${API}/items?${q}`));
  },

  async getItem(id: string): Promise<Item> {
    return j(await fetch(`${API}/items/${id}`));
  },

  async patchItem(
    id: string,
    patch: { title?: string | null; note?: string | null; body_text?: string | null; tags?: string[] },
  ): Promise<Item> {
    return j(
      await fetch(`${API}/items/${id}`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(patch),
      }),
    );
  },

  async deleteItem(id: string): Promise<void> {
    const r = await fetch(`${API}/items/${id}`, { method: "DELETE" });
    if (!r.ok && r.status !== 204)
      throw new Error(`HTTP ${r.status}`);
  },

  async createCapture(data: {
    kind: Kind;
    source_url?: string;
    title?: string;
    note?: string;
    body_text?: string;
    tags?: string[];
    file?: File;
    meta_json?: string;
  }): Promise<Item> {
    const fd = new FormData();
    fd.set("kind", data.kind);
    if (data.source_url) fd.set("source_url", data.source_url);
    if (data.title) fd.set("title", data.title);
    if (data.note) fd.set("note", data.note);
    if (data.body_text) fd.set("body_text", data.body_text);
    if (data.tags?.length) fd.set("tags", data.tags.join(","));
    if (data.meta_json) fd.set("meta_json", data.meta_json);
    if (data.file) fd.set("file", data.file);
    return j(await fetch(`${API}/captures`, { method: "POST", body: fd }));
  },

  async search(q: string): Promise<ItemList> {
    return j(await fetch(`${API}/search?q=${encodeURIComponent(q)}`));
  },

  async tags(): Promise<TagCount[]> {
    return j(await fetch(`${API}/tags`));
  },

  async storageInfo(): Promise<StorageInfo> {
    return j(await fetch(`${API}/storage`));
  },

  async summarizeStream(
    id: string,
    onChunk: (text: string) => void,
  ): Promise<void> {
    const r = await fetch(`${API}/items/${id}/summarize`, { method: "POST" });
    if (!r.ok) throw new Error(`HTTP ${r.status}: ${await r.text()}`);
    const reader = r.body!.getReader();
    const decoder = new TextDecoder();
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      onChunk(decoder.decode(value, { stream: true }));
    }
  },

  async autotagItem(id: string): Promise<string[]> {
    const r = await fetch(`${API}/items/${id}/autotag`, { method: "POST" });
    if (!r.ok) throw new Error(`HTTP ${r.status}: ${await r.text()}`);
    return ((await r.json()) as { tags: string[] }).tags;
  },

  assetUrl(relative: string): string {
    return `${API}/assets/${relative}`;
  },

  exportBackupUrl(): string {
    return `${API}/system/export`;
  },
};
