import { detectKind, postCapture } from "./lib/client";

async function captureActiveTab(tags: string[] = [], note?: string): Promise<void> {
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  if (!tab?.id || !tab.url) throw new Error("nenhuma aba ativa");
  if (!/^https?:/.test(tab.url))
    throw new Error("só funciona em páginas http/https");

  // Screenshot da viewport visível. captureVisibleTab retorna um data URL PNG.
  const dataUrl = await chrome.tabs.captureVisibleTab(tab.windowId, {
    format: "png",
  });
  const base64 = dataUrl.split(",")[1] ?? "";

  // Coletar texto/título da página via content script injetado na hora.
  let pageInfo: { title: string; selection: string; meta: Record<string, string> } = {
    title: tab.title || "",
    selection: "",
    meta: {},
  };
  try {
    const [result] = await chrome.scripting.executeScript({
      target: { tabId: tab.id },
      func: () => {
        const meta: Record<string, string> = {};
        for (const m of document.querySelectorAll("meta")) {
          const n = m.getAttribute("name") || m.getAttribute("property");
          const c = m.getAttribute("content");
          if (n && c) meta[n] = c;
        }
        return {
          title: document.title,
          selection: window.getSelection()?.toString() || "",
          meta,
        };
      },
    });
    if (result?.result) pageInfo = result.result;
  } catch {
    // content script pode falhar em páginas restritas (chrome://, store, etc)
  }

  await postCapture({
    kind: detectKind(tab.url),
    source_url: tab.url,
    title: pageInfo.title,
    body_text: pageInfo.selection || undefined,
    note,
    tags,
    meta_json: JSON.stringify({
      description: pageInfo.meta["description"] || pageInfo.meta["og:description"],
      author: pageInfo.meta["author"] || pageInfo.meta["article:author"],
      site: pageInfo.meta["og:site_name"],
    }),
    screenshot_base64: base64,
    screenshot_filename: `tab-${tab.id}-${Date.now()}.png`,
  });
}

chrome.commands.onCommand.addListener(async (cmd) => {
  if (cmd === "capture-tab") {
    try {
      await captureActiveTab();
      await chrome.action.setBadgeText({ text: "✓" });
      await chrome.action.setBadgeBackgroundColor({ color: "#4a4a6a" });
      setTimeout(() => chrome.action.setBadgeText({ text: "" }), 1500);
    } catch (e) {
      console.error("capture failed", e);
      await chrome.action.setBadgeText({ text: "!" });
      await chrome.action.setBadgeBackgroundColor({ color: "#c44" });
      setTimeout(() => chrome.action.setBadgeText({ text: "" }), 3000);
    }
  }
});

chrome.runtime.onMessage.addListener((msg, _sender, sendResponse) => {
  if (msg?.type === "capture-tab") {
    captureActiveTab(msg.tags || [], msg.note)
      .then(() => sendResponse({ ok: true }))
      .catch((e) => sendResponse({ ok: false, error: String(e) }));
    return true; // async sendResponse
  }
  return false;
});
