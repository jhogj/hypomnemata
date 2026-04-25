# CLAUDE.md — Memória viva do Hypomnemata

> **Primeira ação em toda sessão nova nesta área: ler este arquivo inteiro.**
> Ele diz onde paramos, o que foi decidido, o que está pendente e o que já quebrou.

---

## Protocolo

- **Plano geral**: ver `PLANO.md` (aprovado em 2026-04-21).
- **Ideias novas**: antes de implementar, registrar aqui (aprovada ou rejeitada, com motivo). O usuário pode pedir para salvar uma ideia mesmo rejeitada — respeitar.
- **Decisões que divergem do PLANO.md**: entram aqui datadas, em "Decisões posteriores". Não reescrever o PLANO.md silenciosamente.
- **Bugs**: seção própria, com repro e hipótese.
- **Formato**: leve, datado (`YYYY-MM-DD`), sem cerimônia.

---

## Status atual

- **Onda**: 1 (MVP), 2, 3 entregues. Onda 4 (busca semântica) adiada. Onda 5 (Polimento) em andamento.
- **Rewrite nativo**: Sprint 0, Sprint 1, Sprint 2, Sprint 3, Sprint 4 e Sprint 5 entregues em 2026-04-25. Ver `AGENTS.md` e `native/README.md` para o estado mais novo.
- **Última sessão**: 2026-04-25 — Sprint 5.3 nativa: OCR nativo de imagens/PDFs, `bodyText` e asset derivado criptografado.
- **Próxima tarefa**: Sprint 6.3 — automação, reprocessamento e validação final de IA. Timeline segue como ideia aprovada para o app legado/web.

### Deps externas necessárias (além do `uv sync`)
| Ferramenta | Uso | Instalação |
|---|---|---|
| `yt-dlp` | download vídeos YouTube/Vimeo/tweet | já em `pyproject.toml` via `uv sync` |
| `ffmpeg` | merge streams separadas do YouTube + thumbnails | `brew install ffmpeg` |
| `tesseract` | OCR de imagens | `brew install tesseract tesseract-lang` |
| `gallery-dl` | download fotos de tweets (galeria) | já em `pyproject.toml` via `uv sync` |
| `trafilatura` | scraping de artigos (título, texto, metadados) | já em `pyproject.toml` via `uv sync` |
| `pymupdf` | geração de thumbnails de PDF | já em `pyproject.toml` via `uv sync` |
| `playwright` (chromium) | fallback JS/SPA para scraping de artigos | `uv sync` instala o pacote; depois `uv run playwright install chromium` (baixa ~130MB) |
| `mlx-lm` | servidor LLM local (resumo + tags) | `pip3 install mlx-lm`; depois `python3.12 -m mlx_lm server --model mlx-community/gemma-4-e2b-it-4bit --port 8080` |
| `hf` CLI | autenticação HuggingFace (necessária para baixar modelos MLX) | `brew install hf`; depois `hf auth login` |

### O que existe em código
- `backend/` — FastAPI + SQLAlchemy async + FTS5. Rotas: POST /captures, GET /items (filtros kind/tag/order), GET /items/{id}, PATCH /items/{id}, DELETE /items/{id}, GET /search, GET /tags, GET /assets/{path}, GET /storage, /health. Testes em `backend/tests/` (32 testes).
  - `backend/hypomnemata/ocr.py` — worker OCR: pytesseract (imagens), pypdf (PDFs), roda em thread via `asyncio.to_thread`. Coluna `ocr_status` no Item.
  - `backend/hypomnemata/ytdlp.py` — worker de download: yt-dlp para vídeos e tweets com vídeo; gallery-dl + oEmbed fallback para tweets com foto. Geração de thumbnails (yt-dlp info thumb + ffmpeg fallback). Coluna `download_status` no Item. Cada item usa subdiretório próprio em `assets/{ano}/{mês}/{item_id}/`.
  - `backend/hypomnemata/article.py` — worker de scraping de artigos: trafilatura para extração de título, texto, metadados (autor, data, site) e hero image (og:image). Mesma arquitetura de background task.
  - `backend/hypomnemata/thumbgen.py` — worker de thumbnails: pymupdf (primeira página de PDFs) e ffmpeg (frame 1s de vídeos) para arquivos uploadados via modal.
  - `backend/hypomnemata/routes/storage_info.py` — GET /storage: retorna total de bytes usados pelo diretório de assets.
  - `backend/hypomnemata/llm.py` — cliente LLM agnóstico de provider via `/v1/chat/completions` (OpenAI-compatible). `stream_summary()` e `summarize_sync()` para resumo; `get_autotags()` e `get_autotags_sync()` para tags; `stream_chat()` para conversa multi-turn com contexto do item. Configurado por `HYPO_LLM_URL` e `HYPO_LLM_MODEL`.
  - `backend/hypomnemata/playwright_scraper.py` — `fetch_with_playwright(url)`: renderiza página com Chromium headless, retorna HTML completo. Usado como fallback em `article.py` quando trafilatura não extrai texto suficiente.
  - Rotas novas: `POST /items/{id}/summarize` (streaming), `POST /items/{id}/autotag` (JSON), `POST /items/{id}/links`, `DELETE /items/{id}/links/{target_id}`, `POST /items/{id}/chat` (streaming, persiste histórico).
  - `backend/hypomnemata/crud.py` — `sync_item_links()`: varre `note` + `body_text` via Regex, extrai UUIDs de `[[uuid|display]]` e sincroniza a tabela `item_links` automaticamente ao salvar.
- `webapp/` — React + Vite + Tailwind. Telas: Library (masonry flex + sidebar + busca), CaptureModal (⌘K, tabs URL/Arquivo/Texto), DetailModal (preview + nota/tags editáveis, texto extraído collapsible, galeria de fotos de tweet, excluir). Proxy `/api/*` → backend.
  - `webapp/src/components/NoteEditor.tsx` — Editor de notas com modo Leitura/Edição. Usa `react-mentions` para autocomplete de `[[` com busca FTS5. Grava `[[uuid|título]]` no texto e renderiza o nome atual do item (buscado no banco) no modo leitura. Clicável para navegar entre itens.
- `extension/` — Chrome MV3 via @crxjs/vite-plugin. Popup React (tags/nota/botão), service worker com atalho ⌘⇧Y, `chrome.tabs.captureVisibleTab` + injeção de script pra pegar meta/selection.
- `.gitignore` — na raiz do projeto.

### Comandos rápidos
```
# backend
cd backend && uv sync && uv run pytest              # 42 testes
cd backend && uv run uvicorn hypomnemata.main:app --port 8787

# webapp
cd webapp && npm install && npm run dev             # localhost:5173
cd webapp && npm run typecheck && npm run build

# extensão
cd extension && npm install && npm run build        # carregar dist/ em chrome://extensions

# MLX-LM (servidor IA local — rodar antes do backend quando quiser usar IA)
python3.12 -m mlx_lm server --model mlx-community/gemma-4-e2b-it-4bit --port 8080
```

---

## Decisões tomadas (2026-04-21)

| # | Decisão | Motivo | Substitui |
|---|---|---|---|
| 1 | MVP = fatia vertical mínima (captura → lib, sem OCR/IA/yt-dlp) | Provar o loop antes de camadas | Fase 1-4 em paralelo do esboço |
| 2 | FastAPI | Async nativo, tipagem, streaming de LLM | Flask (esboço original) |
| 3 | Web app em localhost, sem Tauri/Electron | Simplicidade; casa com extensão | Desktop nativo |
| 4 | FTS5 primeiro, embeddings depois | Volume não justifica cedo | Busca semântica desde o início |
| 5 | Chrome MV3 primeiro | 80% dos navegadores; Firefox/Safari depois se precisar | — |
| 6 | Dados em `~/Hypomnemata/`, override via `HYPO_DATA_DIR` | Convenção de home + escape-hatch | — |
| 7 | Sem autenticação | Uso solo, local, `127.0.0.1` apenas | — |
| 8 | UUIDv7 como ID de item | Ordenável por tempo, mantém vantagem do UUID | nanoid |
| 9 | Bun como gerenciador JS (webapp + extensão) | Mais rápido, traz test runner, instala deps em segundos | pnpm |
| 10 | Limite de asset: 100MB (env `HYPO_MAX_ASSET_MB`) | Evita vídeo gigante enchendo disco sem querer | ilimitado |
| 11 | `captured_at` em UTC no banco; UI converte para local | Padrão seguro; FTS não é afetado | local time |
| 12 | Extensão captura só viewport no MVP | `chrome.tabs.captureVisibleTab` é 1 chamada; full-page depois | full-page scroll+stitch |

---

## Decisões posteriores

### 2026-04-21 — Bun não instalado; usando npm por ora
- Decisão 9 (`bun`) permanece, mas no momento da primeira sessão o `bun` não estava instalado no sistema (só `npm 11.12.1` e `node 25.9.0`).
- `package.json` de `webapp/` e `extension/` foi escrito sem lockfile específico.
- Validação de deps feita com `npm install`; o lockfile `package-lock.json` foi mantido.
- **Pendência**: quando o usuário instalar bun, trocar `npm install` → `bun install`, remover `package-lock.json` e deixar só `bun.lockb`. README menciona ambas opções.

### 2026-04-21 — Sem Alembic no MVP
- Plano previa alembic. Enquanto o schema for simples (Item/Tag/ItemTag + FTS), `Base.metadata.create_all` em `init_db()` basta e elimina uma dep + overhead de migration.
- **Quando trocar**: na primeira mudança de schema em produção, ou ao ter dados que não podem ser recriados do zero. Aí adicionar alembic e criar uma migration inicial a partir do schema vigente.

### 2026-04-21 — Ajustes SQLAlchemy async
- Event listener de PRAGMA registrado em `engine.sync_engine` (não em `Engine` abstrato), senão aiosqlite tenta await fora do greenlet context.
- Many-to-many `Item.tags` não é manipulada via relationship em mutações (`item.tags = [...]` dispara lazy-load). Uso `ItemTag` direto + helper `load_tag_names()` pra hidratar tags no response.
- `to_out()` aceita `tag_names=` explícito pra evitar acesso a `item.tags` fora de contexto carregado.

### 2026-04-21 — Atalho da extensão: ⌘⇧Y (não ⌘⇧Space)
- ⌘⇧Space é usado pelo Spotlight/Input Sources no macOS. Chrome `commands` não consegue tomar esse atalho.
- ⌘⇧Y é livre e funciona. Usuário pode remapear em `chrome://extensions/shortcuts`.

### 2026-04-21 — OCR em background (Onda 2, item 6)
- **Arquitetura**: `BackgroundTask` do FastAPI enfileira `ocr_item(item_id)` após commit; roda via `asyncio.to_thread` com engine SQLAlchemy síncrono separado para não disputar o event loop.
- **Imagens**: pytesseract, `lang="por+eng"` com fallback `"eng"`. **PDFs**: pypdf extração nativa; se texto < 150 chars → fallback: PyMuPDF renderiza páginas + Tesseract (para PDFs escaneados).
- **`ocr_status`**: coluna `TEXT` adicionada via `ALTER TABLE` com try/except (SQLite não suporta `IF NOT EXISTS` em colunas). Valores: `NULL` | `"pending"` | `"done"` | `"error:<tipo>"`.
- **Testes**: imports do módulo ficam dentro das funções de teste para evitar que `config.py` seja instanciado antes do fixture `_isolated_data_dir` setar `HYPO_MAX_ASSET_MB`.

### 2026-04-21 — body_text: escondido nos cards, collapsible no modal
- **Motivação**: texto extraído por OCR é longo, técnico e não é bom resumo para card. Só faz sentido no contexto do item aberto.
- **Card.tsx**: removido o bloco que mostrava `body_text` como fallback quando não havia título. Cards sem título mostram só data e tag.
- **DetailModal.tsx**: o bloco estático "Texto extraído" (antes visível apenas para imagens) foi substituído por um collapsible:
  - Condição: `item.body_text && item.ocr_status === "done"` — só aparece quando o OCR realmente produziu texto. Notas e artigos com `body_text` digitado pelo usuário (`ocr_status === null`) não são afetados e continuam visíveis no painel esquerdo.
  - Controle: botão com ▸/▾ alterna `ocrOpen`. Um `useEffect` com `document.addEventListener("mousedown", ...)` fecha o collapsible ao clicar fora do `ref` (`ocrRef`). O listener só é registrado quando `ocrOpen === true` (não desperdiça evento quando fechado).
- **api.ts**: campo `ocr_status: string | null` adicionado ao tipo `Item`.

### 2026-04-21 — Fotos de tweets: gallery-dl + oEmbed
- **Problema**: yt-dlp não suporta tweets com só foto (erro "No video could be found") — é limitação de design do extrator Twitter, não de autenticação.
- **Cascata** (`ytdlp.py`): (1) yt-dlp para tweets com vídeo; (2) gallery-dl para fotos via subprocess; (3) oEmbed (`publish.twitter.com/oembed`) como fallback — baixa `thumbnail_url` com urllib. Texto do tweet extraído da tag `<p>` do HTML oEmbed.
- **Storage**: `asset_path` = primeira imagem/vídeo; `meta_json["media_paths"]` lista todas quando há 2+. Layout em `grid-cols-2` no DetailModal quando múltiplas imagens.

### 2026-04-21 — Play inline de vídeos nos cards

**Funcionalidade**: clicar no ícone ▶ de um card de vídeo troca a thumbnail por um `<video controls autoPlay>` inline — o vídeo toca no próprio card, sem abrir o modal. Clicar em qualquer outra área do card (título, data) abre o DetailModal normalmente.

**Detalhes técnicos** (`Card.tsx`):
- `videoRef = useRef<HTMLVideoElement>` para acessar o player.
- `handlePlayClick` faz `e.stopPropagation()` para não abrir o modal.
- `<div onClick={e.stopPropagation()}>` envolve o `<video>` para que os controles nativos funcionem sem propagar.

### 2026-04-21 — Continuidade de tempo card → DetailModal

**Bug original**: dar play no card e depois abrir o DetailModal fazia o vídeo rodar duas vezes (ambos os players ativos, ambos começando do início).

**Solução** (4 arquivos):
- **Card.tsx**: `handleCardClick()` captura `videoRef.current.currentTime`, pausa o player e reseta `playing = false` antes de chamar `onClick(videoTime)`.
- **Library.tsx**: `onOpenDetail` agora passa `(id, videoTime?)` para cima.
- **App.tsx**: armazena `videoTime` em state, passa como `initialVideoTime` para `DetailModal`. Limpa ao fechar o modal.
- **DetailModal.tsx**: aceita `initialVideoTime?`. Usa `onLoadedMetadata` + `detailVideoRef` para fazer `seek` ao tempo recebido. Flag `videoTimeApplied` garante seek único. `autoPlay` ativado quando há tempo inicial > 0.

**Resultado**: vídeo continua de onde parou no card. Ao fechar o modal, o card volta ao estado de thumbnail (próximo play reinicia do 0).

### 2026-04-21 — Indicador de armazenamento na sidebar

**Funcionalidade**: canto inferior esquerdo da sidebar mostra o total de espaço em disco usado pelos assets (ex: "142.3 MB", "1.25 GB").

**Implementação**:
- **Backend**: novo arquivo `backend/hypomnemata/routes/storage_info.py` com `GET /storage`. Percorre `assets/` recursivamente com `Path.rglob("*")` somando `stat().st_size`. Registrado em `main.py`.
- **Frontend**: `api.storageInfo()` em `api.ts`. `Library.tsx` chama no `refresh()` e passa `storageBytes` para `Sidebar`.
- **Sidebar.tsx**: função `formatBytes()` converte para B/KB/MB/GB. Exibido com ícone de banco de dados (SVG inline) no rodapé fixo da sidebar.

### 2026-04-21 — Auto-refresh quando downloads/OCR terminam

**Bug original**: ao capturar um vídeo ou foto, o card ficava preso em "Baixando..." mesmo após o download concluir no backend. Só aparecia após recarregar a página manualmente.

**Causa**: `Library.tsx` só buscava itens uma vez (no mount ou ao mudar filtros). Não havia mecanismo de re-fetch quando o status de um item mudava no backend.

**Solução** (`Library.tsx`):
- `hasPending = items.some(it => it.download_status === "pending" || it.ocr_status === "pending")`.
- `useEffect` com `setInterval(refresh, 5000)` ativo apenas enquanto `hasPending === true`.
- Quando o backend termina o download/OCR, o próximo poll traz o item atualizado e o card renderiza a thumbnail/imagem/vídeo automaticamente.
- O polling para assim que não há mais itens pendentes (cleanup via `clearInterval`).
### 2026-04-21 — Delete direto do card (lixeira hover)

**Funcionalidade**: ícone de lixeira 🗑️ no canto inferior direito de cada card, visível apenas ao passar o mouse (`opacity-0 group-hover:opacity-100`).

**Implementação** (`Card.tsx` + `Library.tsx`):
- **Card.tsx**: novo prop `onDelete`. Botão com `stopPropagation` (não abre o modal). Confirmação via `confirm()` nativo. SVG de lixeira (Heroicons outline). Hover: fundo vermelho claro + texto vermelho.
- **Library.tsx**: cada `<Card>` recebe `onDelete` que chama `api.deleteItem(it.id)` e depois `refresh()`. Erros são capturados e exibidos no banner de erro existente.
### 2026-04-21 — Scraping de artigos (Onda 2)
- **Worker** (`article.py`): trafilatura para texto + metadados (autor, data, site); hero image baixada de `og:image`. Threshold: texto < 200 chars → scrape insuficiente (item mantido, sem promoção visual). Metadados em `meta_json`: `author`, `pub_date`, `sitename`, `description`, `thumbnail_path`.
- **Dispatch**: `inferKind()` retorna `"article"` para qualquer URL genérica (antes retornava `"bookmark"`). `download_status = "pending"` dispara `scrape_article()` em background.
- **Frontend**: reader view no DetailModal (`kind === "article" && body_text && status === "done"`): hero → título → metadados → parágrafos.

### 2026-04-21 — Thumbnails de uploads e Visualizador de PDF
- **Worker** (`thumbgen.py`): PyMuPDF para primeira página de PDF; ffmpeg para frame em t=1s de vídeo. Salvo como `{ID}.thumb.jpg` (sufixo evita colisão) em `meta_json.thumbnail_path`. `download_status = "pending"` para acionar auto-refresh.
- **Frontend**: viewer nativo de PDF via `<object type="application/pdf">` no DetailModal. Ícone de play só aparece para `isVideoKind` — PDFs com thumbnail não mostram play.

### 2026-04-21 — Visão em Lista e Hover Preview

**Funcionalidade**: Adicionada a capacidade de alternar a visualização da biblioteca entre o formato original "Grid" (Masonry Cards) e o formato "Lista" (linhas detalhadas). Na visão em lista, repousar o mouse sobre um item exibe um preview flutuante (bolha) com a imagem ou miniatura do conteúdo após um breve delay, sem iniciar a reprodução de mídias nativas (apenas imagem estática ou capa).

**Implementação**:
- **Frontend** (`Library.tsx`): Estado `viewMode` persistido no `localStorage` e ícones de toggle de visão adicionados ao header.
- **Frontend** (`ListView.tsx`): Novo componente de lista renderizando os dados dos itens em formato de tabela/linhas.
- **Frontend** (`HoverPreview.tsx`): Lógica de timeout (`onMouseEnter`/`onMouseLeave`) que exibe um portal/elemento posicionado de forma fixa (`fixed`) com a capa daquele item caso haja hover > 600ms. O preview lê as mesmas thumbnails geradas para os cards.

### 2026-04-21 — .gitignore criado
- Arquivo na raiz do projeto. Ignora: `__pycache__/`, `*.py[cod]`, `*.egg-info/`, `.venv/`, `.ruff_cache/`, `.pytest_cache/`, `node_modules/`, `webapp/dist/`, `extension/dist/`, `.DS_Store`, `.env*` (exceto `.env.example`), `.vscode/`, `.idea/`.
- **Não** ignora lockfiles (`package-lock.json`, `uv.lock`) — necessários para builds reprodutíveis.
- `node_modules/` foi adicionado ao git antes do `.gitignore` existir; remoção feita com `git rm -r --cached webapp/node_modules extension/node_modules` antes do primeiro commit.

### 2026-04-21 — yt-dlp em background (Onda 2, item 7)
- **Arquitetura**: mesma do OCR — `BackgroundTask` + `asyncio.to_thread` + engine síncrono separado por chamada.
- **Formato**: preferência `best[ext=mp4]`; fallback `bestvideo+bestaudio` (requer ffmpeg). `noplaylist=True`.
- **`download_status`**: coluna `TEXT` adicionada via `ALTER TABLE` com try/except. Valores: `NULL` | `"pending"` | `"done"` | `"error:missing_dep"` | `"error:too_large"` | `"error:PostprocessingError"` | `"error:<ExcType>"`.
- **Legendas**: segunda chamada separada com `skip_download=True` para evitar abort em HTTP 429. Legenda → `body_text`; descrição → `meta_json["description"]`.

### 2026-04-21 — Masonry: CSS columns → colunas flex explícitas
- **Problema**: `columns-2 md:columns-3 xl:columns-4 2xl:columns-5` (CSS columns) distribui cards em colunas re-balanceando alturas globalmente. Quando uma imagem carrega (lazy: altura 0 → altura real), o browser re-faz o layout inteiro. Em Chrome isso produz um frame com tudo em coluna única (o "blink"). Não é bug de React nem de dados — é comportamento do CSS columns com conteúdo de altura dinâmica.
- **Solução**: substituído por colunas flex explícitas em JS (`Library.tsx`):
  - Hook `useMasonryCols(ref)`: `ResizeObserver` mede a largura do container de grid (não do viewport) e devolve `2 | 3 | 4` colunas. Atualiza só em resize.
  - Distribuição round-robin: `items.filter((_, i) => i % cols === colIdx)` — item 0 → col 0, item 1 → col 1, etc. Balanceia alturas melhor que blocos contíguos.
  - Cada coluna é `<div className="flex min-w-0 flex-1 flex-col gap-4">` — altura dinâmica isolada: uma imagem carregando na col 0 não afeta a col 1.
- **Por que não `grid-template-rows: masonry`**: spec ainda não está em Chrome stable (só Firefox com flag). Ficou para quando tiver suporte amplo.
- **Por que não CSS columns com aspect-ratio fixo**: forçaria crop/letterbox nas imagens, quebrando o visual de masonry variável do wireframe.

---

## Bugs conhecidos

### [2026-04-21] Atalho ⌘⇧Y não funcionou no Chrome
- **Repro**: usuário carregou a extensão e tentou acionar o atalho (relatou "cmd control y").
- **Hipótese**: duas possíveis causas — (a) Chrome não aplica automaticamente a `suggested_key` do manifest; o usuário precisa ir em `chrome://extensions/shortcuts` e configurar manualmente. (b) O usuário pode ter pressionado ⌘⌃Y em vez de ⌘⇧Y.
- **Status**: aberto — não prioritário, só anotar. Workaround: usar o popup (ícone) ou ir em `chrome://extensions/shortcuts`.

Formato quando aparecerem mais:
```
### [2026-MM-DD] <título curto>
- **Repro**: passos
- **Hipótese**: o que eu acho que é
- **Status**: aberto / investigando / resolvido (commit hash)
```

---

### 2026-04-21 — Legendas de vídeo do YouTube (Onda 2, item 7 revisitado)
- Download de legenda separado do vídeo em dois passos: (1) yt-dlp baixa o vídeo sem flags de legenda; (2) segunda chamada com `skip_download=True` tenta legenda em `["pt", "pt-BR"]`. Se falhar (HTTP 429, sem legenda), o vídeo já está salvo — não interrompe o download.
- **Bug corrigido**: flags de legenda na mesma chamada do vídeo causavam abort em HTTP 429 do YouTube.
- Legenda vira `body_text` (preferida sobre descrição para busca FTS5); descrição vai para `meta_json["description"]`. `meta_json["subtitle_lang"]` guarda o idioma detectado.
- Frontend: collapsible "Legenda (pt)" ou "Descrição do vídeo" no DetailModal conforme disponibilidade.

### 2026-04-21 — Polimento da IA: auto-resumo e indicadores
- Auto-resumo disparado no worker (`article.py` / `ytdlp.py`) após ingestão. `meta_json["ai_status"] = "pending"` antes de chamar LLM, removido no `finally`.
- Polling no DetailModal ativado também para `ai_status === "pending"`. Erros do LLM aparecem como badge amber. `<video>` recebe `poster` de `meta_json.thumbnail_path`.

### 2026-04-21 — MLX-LM em vez de Ollama para IA local
- **Problema**: Ollama com qwen2.5:7b (4.7 GB) travou o MacBook Air M2 8GB.
- **Tentativas**: Gemma 4 via Ollama = 7.2 GB (muito grande); Gemma 4 E2B via Ollama não tem Q4_0 disponível.
- **Solução**: MLX-LM com `mlx-community/gemma-4-e2b-it-4bit` = 1.3 GB (formato MLX nativo Apple Silicon). 40–87% mais rápido que Ollama/llama.cpp. Expõe `/v1/chat/completions` (OpenAI-compatible) na porta 8080.
- **Autenticação HuggingFace**: modelo é Apache 2.0 mas exige login HF. `brew install hf && hf auth login`.
- **Config**: `HYPO_LLM_URL=http://localhost:8080`, `HYPO_LLM_MODEL=mlx-community/gemma-4-e2b-it-4bit`. Para Ollama basta trocar a URL para `http://localhost:11434`.
- **Mac Mini M4 16GB**: pode usar `mlx-community/gemma-4-e4b-it-4bit` (~2.5 GB, mais qualidade) via `.env`.

### 2026-04-21 — IA: resumo streaming + auto-tagging (Onda 3)
- `llm.py`: cliente OpenAI-compatible. `stream_summary()` → SSE; `get_autotags_sync()` → lista. `max_tokens` 4096/1024 explícito — sem isso MLX-LM usava 256 tokens e cortava o resumo.
- Tags geradas automaticamente na captura via `get_autotags_sync()` + `set_item_tags_sync()` nos workers. Geradas uma vez; sem regeneração automática nem botão.

### 2026-04-21 — Exportação de Backup em ZIP (Onda 5)
- **Funcionalidade**: Capacidade de baixar o banco de dados inteiro e a pasta de assets (`~/Hypomnemata/`) como um arquivo ZIP.
- **Implementação**: Rota `GET /system/export` no backend, utilizando `shutil.make_archive` em uma thread assíncrona. O arquivo temporário é apagado via `BackgroundTask` do FastAPI após o download.
- **Frontend**: Botão "Exportar Backup" adicionado na Sidebar do webapp, abaixo das estatísticas de disco, apontando para a nova rota via um `<a>` tag `_blank` que abre o modal de salvar nativo do browser.
- **Nota**: Demais itens da Onda 5 (importação, atalho global e empacotamento launchd) foram postergados. A Onda 4 (busca semântica) também foi documentada como adiada no `PLANO.md`.

### 2026-04-21 — Fallback de OCR (Tesseract) para PDFs Escaneados
- **Problema**: `pypdf` consegue extrair texto nativo de PDFs digitais, mas retorna vazio para PDFs que são compostos apenas de imagens escaneadas, tornando-os impossíveis de pesquisar na busca FTS5.
- **Solução** (`ocr.py`): Se o texto extraído nativamente pelo `pypdf` for muito pequeno (menos de 150 caracteres), o sistema trata o arquivo como "PDF escaneado" e executa um fallback.
- **Implementação**: Utiliza a biblioteca `PyMuPDF` (`fitz`) para renderizar cada página do PDF em uma imagem temporária (resolução 2x), salvando no disco temporário com `tempfile`. Em seguida, aplica o Tesseract (`pytesseract`) nelas para extrair o texto. Isso complementa o FTS sem exigir bibliotecas extras além do que o sistema já usava (Tesseract para imagens soltas e PyMuPDF para thumbnails).

## Ideias discutidas

### Aprovadas e implementadas

- **Pastas (Coleções)** — many-to-many, drag & drop nos cards, seleção em lote para adicionar, `SelectionToolbar` e filtro `GET /items?folder=<id>`.
- **Refinamento do DetailModal** — ordem Título → Descrição → Etiquetas → Nota → Fonte; "Texto extraído" e "Legenda" removidos do painel direito; campo "Descrição" ligado a `meta_json["summary"]`, editável.
- **Chat com Documento** — conversa multi-turn com contexto do item (≥ 300 chars) via `POST /items/{id}/chat`; histórico persistido em `meta_json["chat_history"]`.
- **Conexão de Ideias (Zettelkasten)** — `[[uuid|título]]` nas notas com autocomplete via `react-mentions` + FTS5; tabela `item_links` sincronizada em PATCH. UUID permanente; display é cache que resolve o nome atual.
- **Ações em Lote** — modo de seleção com checkboxes, delete e pasta em lote.

### Aprovadas, ainda não implementadas

### 2026-04-22 — Backup Incremental para iCloud

**Mecanismo**: `rsync -a --delete <data_dir>/ <backup_dir>/` — copia só o que mudou. Antes do rsync faz `PRAGMA wal_checkpoint(TRUNCATE)` para consistência do `.db`.

**Config**: `HYPO_BACKUP_DIR` no `backend/.env`. Exemplo: `~/Library/Mobile Documents/com~apple~CloudDocs/Minhas pastas/backup-hypomnemata`.

**Backend**: `config.py` campo `backup_dir: Path | None`; `backup.py` `run_backup()` — WAL checkpoint + subprocess rsync; `POST /system/backup` + `GET /system/backup/status`; startup dispara backup silencioso se configurado.

**Frontend** (`Sidebar.tsx`): botão de sync ao lado do "Exportar ZIP"; estados `idle` / `running` / `ok` (✓ 3s) / `error`; desabilitado com tooltip quando `HYPO_BACKUP_DIR` não configurado.

### 2026-04-21 — Visão de Linha do Tempo (Timeline)
- **Proposta**: visualização alternativa agrupando cards por cabeçalhos temporais dinâmicos ("Hoje", "Semana Passada", "Março de 2026").
- **Decisão**: Aprovada.
- **Motivo**: auxilia na recuperação temporal de itens.

### Rejeitadas (salvas a pedido)
*(nenhuma)*

---

## Referências rápidas

- Esboço técnico original: `descricao_hypomnemata.txt`
- Wireframes: `design/Hypomnemata Wireframe.html` (3 telas)
- Plano aprovado: `PLANO.md`
- Plano (cópia em cache do Claude): `~/.claude/plans/vc-deve-escrever-um-jazzy-blum.md`
