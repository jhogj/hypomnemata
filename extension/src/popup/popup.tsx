import { useEffect, useState } from "react";
import { createRoot } from "react-dom/client";
import { getApiBase, setApiBase } from "../lib/client";

function Popup() {
  const [tags, setTags] = useState("");
  const [note, setNote] = useState("");
  const [base, setBase] = useState("");
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState<{ kind: "ok" | "err"; text: string } | null>(null);
  const [showSettings, setShowSettings] = useState(false);
  const [pageTitle, setPageTitle] = useState("");
  const [pageUrl, setPageUrl] = useState("");

  useEffect(() => {
    void getApiBase().then(setBase);
    void chrome.tabs
      .query({ active: true, currentWindow: true })
      .then(([tab]) => {
        setPageTitle(tab?.title || "");
        setPageUrl(tab?.url || "");
      });
  }, []);

  async function capture() {
    setBusy(true);
    setMsg(null);
    try {
      const resp = await chrome.runtime.sendMessage({
        type: "capture-tab",
        tags: tags
          .split(",")
          .map((t) => t.trim())
          .filter(Boolean),
        note: note || undefined,
      });
      if (resp?.ok) {
        setMsg({ kind: "ok", text: "capturado ✓" });
        setTimeout(() => window.close(), 700);
      } else {
        setMsg({ kind: "err", text: resp?.error || "falha" });
      }
    } catch (e) {
      setMsg({ kind: "err", text: String(e) });
    } finally {
      setBusy(false);
    }
  }

  return (
    <div>
      <div style={{ fontSize: 16, fontWeight: 700, marginBottom: 2 }}>
        Hypomnemata
      </div>
      <div
        style={{
          fontSize: 11,
          color: "#6a6a7a",
          marginBottom: 10,
          overflow: "hidden",
          textOverflow: "ellipsis",
          whiteSpace: "nowrap",
        }}
        title={pageUrl}
      >
        {pageTitle || pageUrl || "aba atual"}
      </div>

      <input
        type="text"
        placeholder="etiquetas (vírgula)"
        value={tags}
        onChange={(e) => setTags(e.target.value)}
        style={inputStyle}
      />
      <textarea
        placeholder="nota (opcional)"
        value={note}
        rows={2}
        onChange={(e) => setNote(e.target.value)}
        style={{ ...inputStyle, resize: "vertical" }}
      />

      <button
        onClick={capture}
        disabled={busy}
        style={{
          width: "100%",
          padding: "8px 10px",
          marginTop: 4,
          border: "none",
          borderRadius: 6,
          background: "#4a4a6a",
          color: "#fafafa",
          fontSize: 14,
          cursor: busy ? "default" : "pointer",
          opacity: busy ? 0.6 : 1,
        }}
      >
        {busy ? "capturando..." : "Capturar aba"}
      </button>

      {msg && (
        <div
          style={{
            marginTop: 8,
            fontSize: 12,
            color: msg.kind === "ok" ? "#2a7a2a" : "#c44",
          }}
        >
          {msg.text}
        </div>
      )}

      <div style={{ marginTop: 10, fontSize: 11, color: "#aaaabc" }}>
        <button
          onClick={() => setShowSettings((s) => !s)}
          style={{
            background: "none",
            border: "none",
            color: "inherit",
            cursor: "pointer",
            padding: 0,
          }}
        >
          {showSettings ? "ocultar" : "configurar backend"}
        </button>
      </div>

      {showSettings && (
        <div style={{ marginTop: 6 }}>
          <input
            type="url"
            value={base}
            onChange={(e) => setBase(e.target.value)}
            onBlur={() => setApiBase(base)}
            placeholder="http://127.0.0.1:8787"
            style={inputStyle}
          />
        </div>
      )}
    </div>
  );
}

const inputStyle: React.CSSProperties = {
  width: "100%",
  padding: "6px 8px",
  marginBottom: 6,
  border: "1px solid #c0bfd0",
  borderRadius: 5,
  fontSize: 13,
  fontFamily: "inherit",
  background: "#fff",
  boxSizing: "border-box",
};

createRoot(document.getElementById("root")!).render(<Popup />);
