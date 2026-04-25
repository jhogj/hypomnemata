export type Kind =
  | "image"
  | "article"
  | "video"
  | "tweet"
  | "bookmark"
  | "note"
  | "pdf";

export interface ItemSummary {
  id: string;
  title: string | null;
  kind: Kind;
  captured_at: string;
}

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
  links?: ItemSummary[];
  backlinks?: ItemSummary[];
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

export interface FolderOut {
  id: string;
  name: string;
  item_count: number;
}

export const api = {
  async listItems(params: {
    kind?: string;
    tag?: string;
    folder?: string;
    limit?: number;
    offset?: number;
  } = {}): Promise<ItemList> {
    const q = new URLSearchParams();
    if (params.kind) q.set("kind", params.kind);
    if (params.tag) q.set("tag", params.tag);
    if (params.folder) q.set("folder", params.folder);
    if (params.limit !== undefined) q.set("limit", String(params.limit));
    if (params.offset !== undefined) q.set("offset", String(params.offset));
    return j(await fetch(`${API}/items?${q}`));
  },

  async getItem(id: string): Promise<Item> {
    return j(await fetch(`${API}/items/${id}`));
  },

  async patchItem(
    id: string,
    patch: { title?: string | null; note?: string | null; body_text?: string | null; summary?: string | null; tags?: string[] },
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

  async clearChatHistory(id: string): Promise<void> {
    const r = await fetch(`${API}/items/${id}/chat`, { method: "DELETE" });
    if (!r.ok && r.status !== 204) throw new Error(`HTTP ${r.status}`);
  },

  async chatStream(
    id: string,
    messages: { role: "user" | "assistant"; content: string }[],
    onChunk: (text: string) => void,
  ): Promise<void> {
    const r = await fetch(`${API}/items/${id}/chat`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ messages }),
    });
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

  async triggerBackup(): Promise<{ ok: boolean; message: string }> {
    const r = await fetch(`${API}/system/backup`, { method: "POST" });
    if (!r.ok) {
      const detail = await r.json().catch(() => ({ detail: "Erro desconhecido" }));
      throw new Error((detail as { detail: string }).detail);
    }
    return r.json();
  },

  async backupStatus(): Promise<{ configured: boolean; backup_dir: string | null }> {
    return j(await fetch(`${API}/system/backup/status`));
  },

  async listFolders(): Promise<FolderOut[]> {
    return j(await fetch(`${API}/folders`));
  },

  async createFolder(name: string): Promise<FolderOut> {
    return j(await fetch(`${API}/folders`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ name }),
    }));
  },

  async renameFolder(id: string, name: string): Promise<FolderOut> {
    return j(await fetch(`${API}/folders/${id}`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ name }),
    }));
  },

  async deleteFolder(id: string): Promise<void> {
    const r = await fetch(`${API}/folders/${id}`, { method: "DELETE" });
    if (!r.ok && r.status !== 204) throw new Error(`HTTP ${r.status}`);
  },

  async addItemsToFolder(folderId: string, itemIds: string[]): Promise<void> {
    const r = await fetch(`${API}/folders/${folderId}/items`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ item_ids: itemIds }),
    });
    if (!r.ok && r.status !== 204) throw new Error(`HTTP ${r.status}`);
  },

  async removeItemFromFolder(folderId: string, itemId: string): Promise<void> {
    const r = await fetch(`${API}/folders/${folderId}/items/${itemId}`, { method: "DELETE" });
    if (!r.ok && r.status !== 204) throw new Error(`HTTP ${r.status}`);
  },

  async getItemFolders(itemId: string): Promise<{ id: string; name: string }[]> {
    return j(await fetch(`${API}/items/${itemId}/folders`));
  },

  async addLink(itemId: string, targetId: string): Promise<void> {
    const r = await fetch(`${API}/items/${itemId}/links`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ target_id: targetId }),
    });
    if (!r.ok) throw new Error(`HTTP ${r.status}: ${await r.text()}`);
  },

  async removeLink(itemId: string, targetId: string): Promise<void> {
    const r = await fetch(`${API}/items/${itemId}/links/${targetId}`, {
      method: "DELETE",
    });
    if (!r.ok && r.status !== 204) throw new Error(`HTTP ${r.status}: ${await r.text()}`);
  },
};
