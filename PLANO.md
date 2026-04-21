# Plano de Implementação — Hypomnemata

> Este é o plano vivo do projeto. Decisões subsequentes ficam no `CLAUDE.md` com data.
> Versão inicial aprovada: 2026-04-21.

## Contexto

Hypomnemata é um repositório local-first de mídia e ideias — captura de tweets, vídeos, artigos, prints e notas num único lugar, para vencer *link rot*, paywalls e deleção de posts. Nome vem do conceito foucaultiano de caderno pessoal de anotações. Usuário é solo, roda em Apple Silicon (macOS), quer soberania de dados sem APIs externas pagas.

Artefatos iniciais: `descricao_hypomnemata.txt` (esboço técnico, 4 fases) e `design/Hypomnemata Wireframe.html` (3 telas pt-BR — Biblioteca masonry, Captura ⌘K, Detalhe com OCR+IA). Ambos são **esboço**, não contrato: decisões abaixo divergem em pontos justificados.

### Decisões de alto nível
- **MVP = fatia vertical mínima**. Captura → persistência → biblioteca, ponta a ponta, sem OCR / IA / yt-dlp. Objetivo da v0.1 é provar o loop.
- **Backend: FastAPI** (não Flask). Async nativo importa quando Ollama e jobs longos entrarem.
- **Frontend: web app em `localhost`** (não Tauri/Electron). Mais simples, casa com a extensão.
- **Busca semântica: fora do MVP**. FTS5 do SQLite primeiro; embeddings depois, se justificarem.

### Suposições (a confirmar — registrar no CLAUDE.md se mudarem)
- UI em **pt-BR**.
- Dados em `~/Hypomnemata/` (configurável via `HYPO_DATA_DIR`).
- Extensão: **Chrome/Chromium MV3** primeiro; Firefox/Safari depois.
- Sem autenticação (usuário único, local).
- Backend roda manualmente via `uvicorn` no MVP; daemon/launchd depois.

---

## Arquitetura resumida

```
┌───────────────────────┐          ┌──────────────────────────┐
│ Extensão Chrome MV3   │          │  Web app (localhost:5173)│
│ React + Vite          │          │  React + Vite + Tailwind │
│ - captura HTML/print  │          │  - biblioteca masonry    │
│ - popup + background  │          │  - modal captura (⌘K)    │
└──────────┬────────────┘          │  - modal detalhe         │
           │  POST /captures       └──────────┬───────────────┘
           ▼                                  ▼
        ┌──────────────────────────────────────────┐
        │ Backend FastAPI (localhost:8787)         │
        │  /captures  /items  /search  /tags       │
        │  SQLAlchemy + FTS5 virtual table         │
        └──────────┬────────────────┬──────────────┘
                   ▼                ▼
          SQLite (metadata     Filesystem
          + FTS5)              ~/Hypomnemata/assets/
          hypomnemata.db       {yyyy}/{mm}/{uuid}.{ext}
```

Três processos separados: **extensão**, **webapp**, **backend**. Webapp e extensão falam só com o backend.

---

## Estrutura de repositório

```
Hypomnemata/
├── CLAUDE.md                 ← memória viva (ler primeiro sempre)
├── PLANO.md                  ← este arquivo
├── README.md
├── descricao_hypomnemata.txt (esboço original)
├── design/                   (wireframes)
├── backend/                  ← FastAPI
│   ├── pyproject.toml        (uv)
│   ├── hypomnemata/
│   │   ├── main.py           (FastAPI app, CORS, lifecycle)
│   │   ├── config.py         (pydantic-settings, HYPO_DATA_DIR)
│   │   ├── db.py             (engine, session, alembic)
│   │   ├── models.py         (Item, Tag, ItemTag, triggers FTS)
│   │   ├── schemas.py        (Pydantic in/out)
│   │   ├── routes/
│   │   │   ├── captures.py
│   │   │   ├── items.py
│   │   │   └── search.py
│   │   └── storage.py        (~/Hypomnemata/assets/yyyy/mm/uuid.ext)
│   └── tests/                (pytest + httpx)
├── webapp/                   ← biblioteca
│   ├── package.json          (vite + react + tailwind)
│   └── src/
│       ├── main.tsx
│       ├── App.tsx
│       ├── lib/api.ts
│       ├── screens/          (Library, CaptureModal, DetailModal)
│       └── components/
└── extension/                ← MV3
    ├── manifest.json
    └── src/
        ├── background.ts     (service worker)
        ├── content.ts        (coleta HTML + metadados)
        ├── popup/            (React)
        └── lib/client.ts     (POST localhost:8787/captures)
```

---

## Modelo de dados

```sql
CREATE TABLE items (
  id           TEXT PRIMARY KEY,
  kind         TEXT NOT NULL,   -- 'image'|'article'|'video'|'tweet'|'bookmark'|'note'|'pdf'
  source_url   TEXT,
  title        TEXT,
  note         TEXT,            -- nota pessoal
  body_text    TEXT,            -- texto extraído
  asset_path   TEXT,            -- relativo a assets/
  meta_json    TEXT,            -- JSON escape-hatch
  captured_at  TEXT NOT NULL,
  created_at   TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE tags (id INTEGER PRIMARY KEY, name TEXT UNIQUE NOT NULL);

CREATE TABLE item_tags (
  item_id TEXT NOT NULL REFERENCES items(id) ON DELETE CASCADE,
  tag_id  INTEGER NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
  PRIMARY KEY (item_id, tag_id)
);

CREATE VIRTUAL TABLE items_fts USING fts5(
  title, note, body_text, content='items', content_rowid='rowid',
  tokenize='unicode61 remove_diacritics 2'
);
-- + triggers AFTER INSERT/UPDATE/DELETE mantendo items_fts sincronizada
```

`remove_diacritics 2` é essencial pra português ("filosofia" casa com "filosófia").

---

## API (MVP)

| Método | Rota | Descrição |
|---|---|---|
| POST | `/captures` | multipart — cria item (opcional com file) |
| GET | `/items` | `?kind=&tag=&limit=&offset=&order=` |
| GET | `/items/{id}` | item completo |
| PATCH | `/items/{id}` | edita title/note/tags |
| DELETE | `/items/{id}` | remove item + asset |
| GET | `/search?q=` | FTS5 bm25 |
| GET | `/tags` | `[{name, count}]` |
| GET | `/assets/{path}` | stream (sandbox em HYPO_DATA_DIR/assets) |

Backend escuta só em `127.0.0.1`. CORS: `chrome-extension://<id>` e `http://localhost:5173`. `/assets/` valida path-traversal.

---

## Ondas

### Onda 1 — Fundação (MVP)
1. Backend FastAPI + SQLAlchemy + Alembic + esquema acima. Rotas CRUD + assets.
2. Webapp: Library masonry + modal detalhe.
3. Extensão MV3: popup "Capturar aba" (screenshot viewport + HTML).
4. Busca FTS5 + trigger de sync.
5. Modal de captura (⌘K) no webapp.

**Entregável**: capturar, ver, buscar.

### Onda 2 — Processamento
6. OCR em background (fila em SQLite ou RQ).
7. yt-dlp para vídeos.
8. Playwright opcional para SPAs pesadas.

### Onda 3 — Inteligência
9. Ollama: `POST /items/{id}/summarize` (disparo manual).
10. Auto-tagging com revisão humana.

### Onda 4 — Busca semântica (se justificar)
11. sqlite-vec + embeddings via Ollama.
12. `/similar/{id}` e merge FTS+vetorial em `/search`.

### Onda 5 — Polimento
13. Export/import (zip com SQLite + assets).
14. Hotkey global (provavelmente migração pra Tauri aqui).
15. Empacotamento / launchd.

---

## Divergências conscientes do esboço

- **FastAPI em vez de Flask** — async.
- **Vite** em vez de CRA — padrão atual.
- **Web app localhost** em vez de desktop nativo — simplicidade.
- **OCR/IA adiados** — schema já prevê os campos; geração depois.
- **Parser específico de tweet** — Onda 2.
- **Atalho global ⌘⇧Space** — MVP usa só `chrome.commands` (não OS-level). OS-level exige Tauri/nativo.

---

## Verificação (fim da Onda 1)

1. `cd backend && uv sync && uv run uvicorn hypomnemata.main:app --port 8787`
2. `cd webapp && pnpm i && pnpm dev` → `http://localhost:5173` vazio.
3. `cd extension && pnpm build` → carregar em `chrome://extensions`.
4. Clicar ícone → "Capturar aba" → 201 OK.
5. Webapp mostra card na masonry.
6. Abrir card → modal com preview/nota/tags editáveis.
7. Buscar título → filtrado.
8. Deletar → some + arquivo removido de `~/Hypomnemata/assets/`.
9. `pytest backend/tests` verde.
10. `GET /assets/../../etc/passwd` → 400/404.
