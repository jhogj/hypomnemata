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

- **Onda**: 1 (MVP) — **entregue** + Onda 2 itens 6, 7 e 8 (OCR + yt-dlp + Playwright) + melhorias de tweet + thumbnails + inline playback + storage + auto-refresh + delete from card + scraping de artigos + thumbgen para uploads.
- **Última sessão**: 2026-04-21 — Playwright como fallback automático de scraping para SPAs (item 8 da Onda 2). 37/37 testes passando.
- **Próxima tarefa**: Onda 3 — Ollama (resumo manual de itens) ou exportação ZIP.

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

### O que existe em código
- `backend/` — FastAPI + SQLAlchemy async + FTS5. Rotas: POST /captures, GET /items (filtros kind/tag/order), GET /items/{id}, PATCH /items/{id}, DELETE /items/{id}, GET /search, GET /tags, GET /assets/{path}, GET /storage, /health. Testes em `backend/tests/` (32 testes).
  - `backend/hypomnemata/ocr.py` — worker OCR: pytesseract (imagens), pypdf (PDFs), roda em thread via `asyncio.to_thread`. Coluna `ocr_status` no Item.
  - `backend/hypomnemata/ytdlp.py` — worker de download: yt-dlp para vídeos e tweets com vídeo; gallery-dl + oEmbed fallback para tweets com foto. Geração de thumbnails (yt-dlp info thumb + ffmpeg fallback). Coluna `download_status` no Item. Cada item usa subdiretório próprio em `assets/{ano}/{mês}/{item_id}/`.
  - `backend/hypomnemata/article.py` — worker de scraping de artigos: trafilatura para extração de título, texto, metadados (autor, data, site) e hero image (og:image). Mesma arquitetura de background task.
  - `backend/hypomnemata/thumbgen.py` — worker de thumbnails: pymupdf (primeira página de PDFs) e ffmpeg (frame 1s de vídeos) para arquivos uploadados via modal.
  - `backend/hypomnemata/routes/storage_info.py` — GET /storage: retorna total de bytes usados pelo diretório de assets.
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
### 2026-04-21 — Scraping de artigos de portais de notícias

**Funcionalidade**: ao capturar uma URL de portal de notícias, o sistema extrai automaticamente título, texto, hero image e metadados do artigo. O usuário pode ler o artigo inteiro dentro do Hypomnemata.

**Implementação**:

- **Backend** (`article.py`): novo worker `scrape_article()`, mesma arquitetura do `ytdlp.py`:
  - `trafilatura.fetch_url()` + `trafilatura.extract()` para texto.
  - `trafilatura.extract_metadata()` para título, autor, data de publicação, nome do site, descrição.
  - Hero image: download da URL `og:image` (campo `metadata.image`) para `assets/{ano}/{mês}/{item_id}/hero.{ext}`.
  - Threshold: texto < 200 chars → scrape considerado insuficiente (item mantido, mas sem promoção visual).
  - Metadados salvos em `meta_json`: `author`, `pub_date`, `sitename`, `description`, `thumbnail_path`.
  - `download_status`: `pending` → `done` / `error:*`.

- **Backend** (`captures.py`): `kind == "article"` + `source_url` + sem `asset_path` → `download_status = "pending"` → enfileira `scrape_article()`. Dispatch separado do `download_video()` via check de kind.

- **Frontend** (`CaptureModal.tsx`): `inferKind()` retorna `"article"` para URLs genéricas (antes retornava `"bookmark"`). Toda URL que não é tweet/vídeo agora tenta scraping.

- **Frontend** (`Card.tsx`): `"article"` adicionado ao array `hasImage` → hero images aparecem nos cards.

- **Frontend** (`DetailModal.tsx`): **reader view** para artigos:
  - Condição: `kind === "article" && body_text && download_status === "done"`.
  - Hero image no topo (se houver `asset_path`).
  - Título em `<h1>` bold.
  - Metadados (sitename, author, pub_date) em linha discreta.
  - Separador horizontal.
  - Texto do artigo formatado como parágrafos (`\n\n` → `<p>`) com scroll nativo.
  - `downloadLabel()` atualizado: `"Extraindo artigo..."` para pending, `"trafilatura não instalado"` para missing_dep.

**Dep nova**: `trafilatura>=2.0` em `pyproject.toml`.

### 2026-04-21 — Thumbnails de uploads e Visualizador de PDF

**Funcionalidade**: Quando o usuário faz upload manual de um PDF ou Vídeo, o sistema agora gera e mostra uma thumbnail no card (primeira página do PDF ou frame em `t=1s` do vídeo). Ao clicar em um PDF, ele abre direto no modal para leitura, em vez de só mostrar um link de download.

**Implementação**:
- **Backend** (`thumbgen.py`): Novo background worker. Usa `PyMuPDF` (`fitz`) para PDFs e `ffmpeg` para vídeos. A imagem é salva como `thumb.jpg` na pasta do asset e registrada no `meta_json.thumbnail_path`. O item fica como `download_status = "pending"` até terminar para usar o auto-refresh já implementado no webapp.
- **Backend** (`captures.py`): Arquivos uploadados do tipo PDF/Video agora passam pelo `download_status = "pending"` e disparam o `generate_upload_thumbnail()`.
- **Frontend** (`Card.tsx`): Removido o bug onde PDFs mostravam botão de "play" sobreposto. O ícone de play só renderiza se `isVideoKind` for verdadeiro, independentemente de ter thumbnail.
- **Frontend** (`Card.tsx`): Aprimorada a UX dos vídeos na visão de cards. Se um vídeo estiver tocando no grid e o usuário clicar fora do card ou der play em outro vídeo, o player do primeiro é desativado e ele volta a mostrar apenas a miniatura, evitando múltiplos vídeos tocando simultaneamente e mantendo o grid limpo.
- **Frontend** (`DetailModal.tsx`): Adicionado `<object type="application/pdf">` para renderizar o leitor nativo de PDFs do navegador no painel esquerdo do modal.
- **Testes** (`test_ytdlp.py`): O teste `test_capture_video_file_only_no_download` foi atualizado para esperar o `download_status = "pending"` em uploads diretos de vídeo, refletindo a nova regra para acionar o `thumbgen`.

- **Bugfix**: Corrigido um problema onde uploads de diferentes itens sobrescreviam a mesma miniatura na pasta do mês (colisão de `thumb.jpg`). A miniatura agora usa o nome original com o sufixo `.thumb.jpg` (ex: `ID.thumb.jpg`).

**Dep nova**: `pymupdf>=1.24` adicionada em `pyproject.toml`.

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
