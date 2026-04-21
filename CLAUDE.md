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

- **Onda**: 1 (MVP) — **entregue** + Onda 2 itens 6 e 7 (OCR + yt-dlp) + melhorias de tweet (imagens, galeria, texto) + thumbnails de vídeo nos cards.
- **Última sessão**: 2026-04-21 — thumbnails de vídeo nos cards (YouTube thumb via yt-dlp info, ffmpeg frame extraction como fallback para Twitter/outros). 32/32 testes passando.
- **Próxima tarefa**: nenhuma pendente crítica. Possíveis próximos: busca semântica, exportação, notificações de download concluído.

### Deps externas necessárias (além do `uv sync`)
| Ferramenta | Uso | Instalação |
|---|---|---|
| `yt-dlp` | download vídeos YouTube/Vimeo/tweet | já em `pyproject.toml` via `uv sync` |
| `ffmpeg` | merge streams separadas do YouTube | `brew install ffmpeg` |
| `tesseract` | OCR de imagens | `brew install tesseract tesseract-lang` |
| `gallery-dl` | download fotos de tweets (galeria) | `uv add gallery-dl` ou `pip install gallery-dl` |

### O que existe em código
- `backend/` — FastAPI + SQLAlchemy async + FTS5. Rotas: POST /captures, GET /items (filtros kind/tag/order), GET /items/{id}, PATCH /items/{id}, DELETE /items/{id}, GET /search, GET /tags, GET /assets/{path}, /health. Testes em `backend/tests/` (32 testes).
  - `backend/hypomnemata/ocr.py` — worker OCR: pytesseract (imagens), pypdf (PDFs), roda em thread via `asyncio.to_thread`. Coluna `ocr_status` no Item.
  - `backend/hypomnemata/ytdlp.py` — worker de download: yt-dlp para vídeos e tweets com vídeo; gallery-dl + oEmbed fallback para tweets com foto. Coluna `download_status` no Item. Cada item usa subdiretório próprio em `assets/{ano}/{mês}/{item_id}/`.
- `webapp/` — React + Vite + Tailwind. Telas: Library (masonry flex + sidebar + busca), CaptureModal (⌘K, tabs URL/Arquivo/Texto), DetailModal (preview + nota/tags editáveis, texto extraído collapsible, galeria de fotos de tweet, excluir). Proxy `/api/*` → backend.
- `extension/` — Chrome MV3 via @crxjs/vite-plugin. Popup React (tags/nota/botão), service worker com atalho ⌘⇧Y, `chrome.tabs.captureVisibleTab` + injeção de script pra pegar meta/selection.
- `.gitignore` — na raiz do projeto.

### Comandos rápidos
```
# backend
cd backend && uv sync && uv run pytest              # 32 testes
cd backend && uv run uvicorn hypomnemata.main:app --port 8787

# webapp
cd webapp && npm install && npm run dev             # localhost:5173
cd webapp && npm run typecheck && npm run build

# extensão
cd extension && npm install && npm run build        # carregar dist/ em chrome://extensions
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
- **Arquivo novo**: `backend/hypomnemata/ocr.py`.
- **Como funciona**: após o commit de uma captura com asset (imagem ou PDF), o route handler enfileira `ocr_item(item_id)` como `BackgroundTask` do FastAPI. `ocr_item` chama `asyncio.to_thread(_run_ocr_sync, item_id)`, que roda numa thread do pool e usa um engine SQLAlchemy **síncrono** separado (`settings.sync_db_url`) para não disputar o event loop. O engine síncrono é criado e descartado por chamada (simples, sem pool sharing com o engine async).
- **Imagens** (`_ocr_image`): `pytesseract.image_to_string(img, lang="por+eng")`, com fallback para `lang="eng"` se `por` não estiver instalado. Requer Tesseract no PATH (`brew install tesseract tesseract-lang`).
- **PDFs** (`_ocr_pdf`): `pypdf.PdfReader` — extração de texto nativo. Não renderiza páginas (sem poppler). PDFs escaneados sem texto ficam com `body_text` vazio, não geram erro.
- **`ocr_status`**: nova coluna `TEXT` no Item. Valores: `NULL` (sem asset ou tipo não suportado), `"pending"` (ao fazer commit da captura), `"done"` (OCR concluído), `"error:<tipo>"` (falhou). A migration é um `ALTER TABLE items ADD COLUMN ocr_status TEXT` com try/except em `init_db()` — SQLite não suporta `IF NOT EXISTS` em colunas.
- **Deps novas**: `pytesseract>=0.3`, `Pillow>=10.0`, `pypdf>=4.0` em `pyproject.toml`.
- **FTS5**: o trigger `items_au` já existente (`AFTER UPDATE ON items`) mantém o FTS sincronizado com o novo `body_text` que o OCR grava via `UPDATE` direto — nenhuma mudança necessária no trigger.
- **Testes em `tests/test_ocr.py`**: imports do módulo hypomnemata ficam DENTRO das funções de teste (não no topo do arquivo) para evitar que `config.py` seja instanciado na fase de coleta do pytest, antes de o fixture `_isolated_data_dir` definir `HYPO_MAX_ASSET_MB=10`. Isso era bug pré-existente que só apareceu ao adicionar o arquivo de teste.

### 2026-04-21 — body_text: escondido nos cards, collapsible no modal
- **Motivação**: texto extraído por OCR é longo, técnico e não é bom resumo para card. Só faz sentido no contexto do item aberto.
- **Card.tsx**: removido o bloco que mostrava `body_text` como fallback quando não havia título. Cards sem título mostram só data e tag.
- **DetailModal.tsx**: o bloco estático "Texto extraído" (antes visível apenas para imagens) foi substituído por um collapsible:
  - Condição: `item.body_text && item.ocr_status === "done"` — só aparece quando o OCR realmente produziu texto. Notas e artigos com `body_text` digitado pelo usuário (`ocr_status === null`) não são afetados e continuam visíveis no painel esquerdo.
  - Controle: botão com ▸/▾ alterna `ocrOpen`. Um `useEffect` com `document.addEventListener("mousedown", ...)` fecha o collapsible ao clicar fora do `ref` (`ocrRef`). O listener só é registrado quando `ocrOpen === true` (não desperdiça evento quando fechado).
- **api.ts**: campo `ocr_status: string | null` adicionado ao tipo `Item`.

### 2026-04-21 — Fotos de tweets: gallery-dl + oEmbed + extração de texto

**Problema raiz**: yt-dlp é um baixador de *vídeos*. Para tweets com só foto ele retorna `DownloadError: No video could be found in this tweet` — não é falha de autenticação, é limitação de design do extrator Twitter do yt-dlp.

**Solução em cascata** (`ytdlp.py`):
1. Tenta yt-dlp normalmente (funciona para tweets com vídeo).
2. Se yt-dlp levanta `DownloadError` com "No video" para um tweet → chama `_download_tweet_images()`:
   - **gallery-dl** (`pip install gallery-dl` / `uv add gallery-dl`): baixa todas as fotos da galeria via subprocess. Renomeia para `001.jpg`, `002.jpg`, etc. Retorna lista de paths.
   - **oEmbed fallback** (sem dep extra): `https://publish.twitter.com/oembed?url=...` → campo `thumbnail_url` → download direto da imagem com `urllib.request`. Acessa qualidade `name=orig`.
3. Texto do tweet extraído do HTML da resposta oEmbed em ambos os caminhos: parseia a tag `<p>` do blockquote com `html.parser` da stdlib; remove links `pic.twitter.com/xxx` (já representados pela imagem).

**Storage**: cada item usa subdiretório próprio `assets/{ano}/{mês}/{item_id}/` — múltiplos arquivos sem conflito de nome. `asset_path` = primeira imagem (ou vídeo se existir). Quando há 2+ arquivos → `meta_json["media_paths"]` lista todos os caminhos.

**Frontend (`DetailModal.tsx`)**:
- Painel esquerdo: se `meta_json.media_paths` tiver 2+ itens → `grid-cols-2`. Com 3 imagens: primeira tem `row-span-2` (layout estilo Twitter).
- `downloadLabel()`: removido catch-all que mostrava "Tweet sem vídeo para baixar" para qualquer erro — escondia a causa real. Agora mostra o erro completo.
- Card.tsx inalterado — `asset_path` já aponta para a primeira imagem.

**Testes**: `_find_video_file` → `_find_media_files` (3 unit tests) + teste de graceful fallback quando gallery-dl e rede estão ausentes. 32/32 passando.

### 2026-04-21 — Thumbnails de vídeo nos cards

**Problema raiz**: cards de itens do tipo `video` (YouTube, Vimeo) e tweets com vídeo mostravam apenas o placeholder "vídeo" — sem nenhuma imagem de preview, tornando a biblioteca masonry visualmente pobre.

**Solução** (`ytdlp.py` + `Card.tsx`):
- **Backend**: nova função `_generate_thumbnail()` chamada após o download do vídeo:
  1. **YouTube/Vimeo**: baixa a thumbnail da URL contida no dict `info` retornado por `yt-dlp.extract_info()` (campo `thumbnail`). Sempre disponível.
  2. **Fallback (Twitter/outros)**: extrai um frame do vídeo em `t=1s` via `ffmpeg -frames:v 1 -q:v 2 thumb.jpg`. Requer `ffmpeg` no PATH.
  3. Thumbnail salva como `thumb.jpg` no subdiretório do item (`assets/{ano}/{mês}/{item_id}/thumb.jpg`). Caminho relativo armazenado em `meta_json.thumbnail_path`.
- **Frontend**: `Card.tsx` lê `meta_json.thumbnail_path` via `getThumbnailPath()`. Se disponível, exibe a thumbnail com um overlay de ícone de play (▶ com fundo escuro semi-transparente, escala no hover). Cards com `download_status === "pending"` mostram spinner animado em vez de placeholder estático.

**Nota**: thumbnails são geradas apenas para itens **novos** (download futuro). Itens existentes mantêm o placeholder até que sejam re-capturados ou um script de backfill seja rodado.

### 2026-04-21 — .gitignore criado
- Arquivo na raiz do projeto. Ignora: `__pycache__/`, `*.py[cod]`, `*.egg-info/`, `.venv/`, `.ruff_cache/`, `.pytest_cache/`, `node_modules/`, `webapp/dist/`, `extension/dist/`, `.DS_Store`, `.env*` (exceto `.env.example`), `.vscode/`, `.idea/`.
- **Não** ignora lockfiles (`package-lock.json`, `uv.lock`) — necessários para builds reprodutíveis.
- `node_modules/` foi adicionado ao git antes do `.gitignore` existir; remoção feita com `git rm -r --cached webapp/node_modules extension/node_modules` antes do primeiro commit.

### 2026-04-21 — yt-dlp em background (Onda 2, item 7)
- **Arquivo novo**: `backend/hypomnemata/ytdlp.py`.
- **Gatilho**: `kind == "video"` E `source_url` preenchida → `download_status = "pending"` antes do commit → `BackgroundTask` enfileira `download_video(item_id)` após o commit. Mesma arquitetura do OCR: thread pool via `asyncio.to_thread`, engine SQLAlchemy síncrono separado criado e descartado por chamada.
- **Formato de saída**: preferência `best[ext=mp4]` (stream único, sem merge). Fallback: `bestvideo[ext=mp4]+bestaudio[ext=m4a]` (requer ffmpeg para merge). `noplaylist=True` para não baixar playlists inteiras por acidente.
- **Arquivo salvo em**: `assets/yyyy/mm/{item_id}/{nnn}.{ext}` — subdiretório por item. Após o download, se havia um screenshot (capturado pela extensão), ele é deletado e `asset_path` é atualizado para o vídeo/imagem primária.
- **Metadados extraídos**: `title` (se vazio no item) e `description` → `body_text` (sempre sobrescreve para vídeos, limitado a 5000 chars). Título e descrição vêm do objeto `info` retornado por `ydl.extract_info`.
- **`download_status`**: nova coluna `TEXT`. Valores: `NULL`, `"pending"`, `"done"`, `"error:missing_dep"`, `"error:too_large"`, `"error:PostprocessingError"` (ffmpeg ausente), `"error:<ExcType>"`. Migration via `ALTER TABLE` com try/except em `init_db()`.
- **Deps novas**: `yt-dlp>=2024.1` em `pyproject.toml`. `ffmpeg` externo necessário para maioria dos vídeos do YouTube (`brew install ffmpeg`). Sem ffmpeg, status vira `error:PostprocessingError` e o modal exibe mensagem específica.
- **Extensão** (`client.ts`): `detectKind` atualizado para retornar `"video"` para YouTube (`youtube.com/watch`, `/shorts`, `/live`, `youtu.be`) e Vimeo (`vimeo.com/\d`). Vem antes dos checks de extensão de arquivo, depois do check de tweet (Twitter/X continua como `"tweet"`).
- **Webapp** (`DetailModal.tsx`):
  - Painel esquerdo: `<video controls>` para assets com extensão de vídeo. Durante `download_status === "pending"` sem asset ainda, mostra "Baixando vídeo..." no centro.
  - Painel direito: indicador discreto com mensagens legíveis por status (`"pending"` → fundo cinza; erro → fundo âmbar com texto específico incluindo instrução de ffmpeg).
- **Testes em `tests/test_ytdlp.py`**: `_find_video_file` (unit), 4 testes de integração via API, 1 teste de `_run_ytdlp_sync` com `builtins.__import__` mockado para simular yt-dlp ausente.

### 2026-04-21 — Masonry: CSS columns → colunas flex explícitas
- **Problema**: `columns-2 md:columns-3 xl:columns-4 2xl:columns-5` (CSS columns) distribui cards em colunas re-balanceando alturas globalmente. Quando uma imagem carrega (lazy: altura 0 → altura real), o browser re-faz o layout inteiro. Em Chrome isso produz um frame com tudo em coluna única (o "blink"). Não é bug de React nem de dados — é comportamento do CSS columns com conteúdo de altura dinâmica.
- **Solução**: substituído por colunas flex explícitas em JS (`Library.tsx`):
  - Hook `useMasonryCols(ref)`: `ResizeObserver` mede a largura do container de grid (não do viewport) e devolve `2 | 3 | 4` colunas. Atualiza só em resize.
  - Distribuição round-robin: `items.filter((_, i) => i % cols === colIdx)` — item 0 → col 0, item 1 → col 1, etc. Balanceia alturas melhor que blocos contíguos.
  - Cada coluna é `<div className="flex min-w-0 flex-1 flex-col gap-4">` — altura dinâmica isolada: uma imagem carregando na col 0 não afeta a col 1.
- **Por que não `grid-template-rows: masonry`**: spec ainda não está em Chrome stable (só Firefox com flag). Ficou para quando tiver suporte amplo.
- **Por que não CSS columns com aspect-ratio fixo**: forçaria crop/letterbox nas imagens, quebrando o visual de masonry variável do wireframe.

---

## Questões em aberto

*(todas as 5 iniciais resolvidas em 2026-04-21 — ver decisões 8-12)*

---

## Bugs conhecidos

### [2026-04-21] Atalho ⌘⇧Y não funcionou no Chrome
- **Repro**: usuário carregou a extensão e tentou acionar o atalho (relatou "cmd control y").
- **Hipótese**: duas possíveis causas — (a) Chrome não aplica automaticamente a `suggested_key` do manifest; o usuário precisa ir em `chrome://extensions/shortcuts` e configurar manualmente. (b) O usuário pode ter pressionado ⌘⌃Y em vez de ⌘⇧Y.
- **Status**: aberto — não prioritário, só anotar. Workaround: usar o popup (ícone) ou ir em `chrome://extensions/shortcuts`.

### [2026-04-21] Tweet do x.com salvo como kind="bookmark"
- **Repro**: salvar uma página de `https://x.com/...` gera um item com `kind="bookmark"` em vez de `kind="tweet"`.
- **Hipótese**: regex em `extension/src/lib/client.ts:60` — `(?:^|\.)x\.com\/` — exige ponto ou início de string antes de `x.com`. A URL real é `https://x.com/...` (tem `://x`, não `.x`), então o match falha e cai no fallback `"bookmark"`.
- **Status**: resolvido — trocado para `/\/\/(?:www\.)?x\.com\//`. Extensão rebuildada.

### [2026-04-21] Masonry piscava e colapsava para coluna única
- **Repro**: cards aparecem em múltiplas colunas, depois piscam e ficam todos empilhados verticalmente; recarregar a página restaura o layout.
- **Causa**: CSS `columns` redistribui todos os cards globalmente toda vez que qualquer card muda de altura. Imagens lazy-loaded começam com altura 0 e crescem ao carregar — cada carga dispara um re-flow do layout inteiro. Em Chrome esse re-flow produzia um frame com coluna única visível ao usuário.
- **Status**: resolvido — substituído por colunas flex explícitas (ver decisão "Masonry: CSS columns → colunas flex explícitas").

### [2026-04-21] Fotos de tweet não apareciam (yt-dlp não suporta imagens estáticas)
- **Repro**: salvar URL de tweet com só foto → `download_status = "error:DownloadError: No video could be found"` → modal mostrava "Tweet sem vídeo para baixar" (mensagem de erro genérica mascarava o problema).
- **Causa**: yt-dlp é um baixador de vídeos; o extrator do Twitter retorna erro quando não há vídeo, mesmo que haja fotos. Além disso, o `downloadLabel()` usava um catch-all para qualquer erro em tweets, escondendo a mensagem real.
- **Status**: resolvido — fallback para gallery-dl + oEmbed; `downloadLabel` agora mostra o erro completo.

Formato quando aparecerem mais:
```
### [2026-MM-DD] <título curto>
- **Repro**: passos
- **Hipótese**: o que eu acho que é
- **Status**: aberto / investigando / resolvido (commit hash)
```

---

## Ideias discutidas

### Aprovadas (ainda não implementadas)
*(nenhuma além das que já estão no PLANO.md)*

### Rejeitadas (salvas a pedido)
*(nenhuma)*

Formato quando aparecerem:
```
### [2026-MM-DD] <ideia>
- **Proposta**: descrição
- **Decisão**: aprovada / rejeitada / adiada
- **Motivo**: por quê
```

---

## Referências rápidas

- Esboço técnico original: `descricao_hypomnemata.txt`
- Wireframes: `design/Hypomnemata Wireframe.html` (3 telas)
- Plano aprovado: `PLANO.md`
- Plano (cópia em cache do Claude): `~/.claude/plans/vc-deve-escrever-um-jazzy-blum.md`
