# AGENTS.md — Memória viva do Hypomnemata

> **Primeira ação em toda sessão nova nesta área: ler este arquivo inteiro.**
> Ele diz onde paramos, o que foi decidido, o que está pendente e o que já quebrou.

---

## Protocolo

- **Plano geral**: ver `PLANO.md` (aprovado em 2026-04-21).
- **Ideias novas**: antes de implementar, registrar aqui (aprovada ou rejeitada, com motivo). O usuário pode pedir para salvar uma ideia mesmo rejeitada — respeitar.
- **Decisões que divergem do PLANO.md**: entram aqui datadas, em "Decisões posteriores". Não reescrever o PLANO.md silenciosamente.
- **Bugs**: seção própria, com repro e hipótese.
- **Formato**: leve, datado (`YYYY-MM-DD`), sem cerimônia.
- **Rewrite nativo / Sprint 1**: rotina padrão é entregar em micro-passos. Para cada micro-passo: implementar só aquele recorte, atualizar `AGENTS.md`/docs, validar build/checks, reportar ao usuário e parar antes de continuar. Exceção registrada: em 2026-04-25 o usuário pediu explicitamente fechar o restante da sprint inteiro.
- **Sem contorno silencioso**: se faltar instalação, permissão, configuração local ou assinatura, parar e informar o comando exato para o usuário rodar.

---

## Status atual

- **Onda**: 1 (MVP), 2, 3 entregues. Onda 4 (busca semântica) adiada. Onda 5 (Polimento) em andamento.
- **Rewrite nativo**: Sprint 0, Sprint 1, Sprint 2, Sprint 3, Sprint 4.1 e Sprint 4.2 entregues em 2026-04-25.
- **Última sessão**: 2026-04-25 — Sprint 4.2: UI de pastas e operações de organização.
- **Próxima tarefa**: Sprint 4.3 — Zettelkasten no detalhe: links clicáveis/autocomplete básico e backlinks. Timeline segue como ideia aprovada para o app legado/web.

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

### 2026-04-25 — Rewrite nativo macOS iniciado
- **Decisão**: nova trilha em `native/` com Swift/SwiftUI, macOS 14+, Apple Silicon, módulos Core/Data/Media/Ingestion/AI/Backup/App.
- **Motivo**: a aplicação foi comprada e precisa virar app leve de macOS; FastAPI/React passam a ser referência funcional, não destino final.
- **Segurança**: produção deve falhar fechada sem SQLCipher; após a etapa SQLCipher real, os checks locais também usam banco criptografado.
- **Extensão Chrome/MV3**: descartada do produto novo. Captura passa a ser interna ao app e futuramente via Share/Services nativos.
- **Dados antigos**: sem migração no primeiro release nativo.

### 2026-04-25 — SQLCipher real no app nativo
- **Decisão**: GRDB foi vendorizado em `native/Vendor/GRDBSQLCipher` com manifest SwiftPM próprio para linkar `SQLCipher.swift` 4.14.0.
- **Motivo**: GRDB 7.10.0 documenta que SwiftPM + SQLCipher exige fork/manifest modificado; dependência direta em `groue/GRDB.swift` linka SQLite do sistema e não criptografa.
- **Validação**: `HypomnemataNativeChecks` abre banco com SQLCipher e verifica que `/usr/bin/sqlite3` não consegue ler `Hypomnemata.sqlite`.
- **Sem fallback**: removido o toggle de desenvolvimento plaintext da UI; produção exige SQLCipher.

### 2026-04-25 — Sprint 1.1: chave de assets persistida no vault
- **Implementado**: `NativeDatabase.loadOrCreateAssetKeyData()` cria uma chave AES de 32 bytes com `SecRandomCopyBytes`, salva em `settings.asset_key_v1` como Base64 e reutiliza a mesma chave após reabrir o banco.
- **Motivo**: assets criptografados precisam de chave estável protegida pelo SQLCipher, não chave ad hoc em memória nem arquivo plaintext.
- **App**: no unlock, `AppModel` cria `EncryptedAssetStore` usando a chave persistida no vault.
- **Validação esperada**: `HypomnemataNativeChecks` confirma tamanho da chave, estabilidade dentro da sessão e estabilidade após reopen do banco.

### 2026-04-25 — Sprint 1.2: limpeza de cache temporário
- **Implementado**: `AppModel.lock()` chama `EncryptedAssetStore.clearTemporaryCache()` antes de fechar o banco e descartar chaves/repositórios.
- **Quit**: `HypomnemataNativeApp` escuta `NSApplication.willTerminateNotification` e chama `prepareForQuit()` para limpar cache antes do app encerrar.
- **Motivo**: arquivos descriptografados para previews futuros de PDFKit/AVPlayer não podem permanecer em `TemporaryCache` após lock/quit.
- **Validação esperada**: `HypomnemataNativeChecks` confirma que `clearTemporaryCache()` remove arquivo temporário descriptografado e recria o diretório de cache vazio.

### 2026-04-25 — Sprint 1.3: lock idempotente e fail-closed
- **Implementado**: `AppModel.lock()` agora coleta erro de limpeza de cache e erro de fechamento do banco, mas sempre descarta `database`, `repository`, `assetStore`, `appPaths`, seleção, query, itens e modal de captura.
- **Motivo**: lock não pode deixar chaves/repositórios vivos se uma etapa auxiliar falhar.
- **Estado**: se houve erro durante lock, o app entra em `.failed(message)` depois de descartar recursos; caso contrário entra em `.locked`.
- **Validação esperada**: `TemporaryCacheCleaner` foi extraído para `HypomnemataMedia` e o check valida que limpar cache inexistente é idempotente e recria o diretório.

### 2026-04-25 — Sprint 1.4: auto-lock por inatividade e eventos do macOS
- **Implementado**: `AppModel` instala monitor local de eventos AppKit para teclado, mouse, scroll e mudança de modifiers. Cada atividade reinicia timer de 15 minutos enquanto o vault está desbloqueado.
- **Eventos de segurança**: `NSWorkspace.willSleepNotification`, `screensDidSleepNotification` e `sessionDidResignActiveNotification` bloqueiam o vault imediatamente quando o Mac vai dormir, a tela dorme ou a sessão perde atividade.
- **Motivo**: cumprir Sprint 1 sem depender só de lock manual; a conexão SQLCipher, repositórios, `AssetStore` e cache temporário saem de memória no lock.
- **Nota técnica**: o `deinit` explícito de monitores foi removido porque Swift 6 trata esses objetos AppKit/Objective-C como não-Sendable em `deinit` não-isolado. `AppModel` vive pelo ciclo do app; limpeza crítica continua em lock/quit.

### 2026-04-25 — Sprint 1.5: troca de senha do vault
- **Implementado**: `NativeDatabase.changePassphrase(to:)` usa `db.changePassphrase(...)` do GRDB/SQLCipher após `PRAGMA wal_checkpoint(TRUNCATE)`.
- **UI**: sidebar ganhou "Trocar senha", abrindo sheet com senha atual, nova senha e confirmação. Senha vazia e confirmação divergente geram erro local.
- **Verificação da senha atual**: antes do rekey, o app tenta abrir o vault com a senha atual informada. Se falhar, não chama `changePassphrase`.
- **Garantia**: a chave de assets permanece armazenada dentro do banco criptografado e não muda com a troca de senha.

### 2026-04-25 — Sprint 1.6: checks finais de vault, assets, cache e rekey
- **Implementado em `HypomnemataNativeChecks`**:
  - cria vault SQLCipher real;
  - valida CRUD, tags, FTS5 com diacríticos e dependências esperadas;
  - cria chave de assets persistida no banco;
  - grava asset AES-GCM, confirma que o arquivo em disco não é plaintext e que descriptografa corretamente;
  - gera cache temporário descriptografado e confirma remoção no cleanup;
  - troca senha do vault, valida que a senha antiga não abre mais;
  - reabre com a senha nova, confirma que item, chave de assets e asset criptografado continuam válidos;
  - confirma que `/usr/bin/sqlite3` comum não lê o banco.
- **Validação rodada**:
  - `swift run --disable-sandbox HypomnemataNativeChecks` — passou.
  - `swift build --disable-sandbox --product HypomnemataMacApp` — passou.
- **Status**: Sprint 1 concluída. Próxima etapa de produto: Sprint 2 — Biblioteca Nativa.

### 2026-04-25 — Sprint 2.1/2.2: queries da biblioteca e sidebar nativa
- **Implementado em `SQLiteItemRepository`**:
  - busca FTS5 agora aceita `ItemListFilter`, permitindo combinar query textual com tipo, tag e pasta;
  - listagem também suporta filtro combinado por `kind`, `tag` e `folderID`;
  - `totalItemCount()`, `itemCountsByKind()`, `tagCounts()`, `listFolders()`, `createFolder(name:)` e `addItems(_:toFolder:)`;
  - nomes vazios de pasta são rejeitados com `DataError.emptyFolderName`.
- **Implementado em `AppModel`**:
  - estado de filtros ativos: tipo, tag e pasta;
  - contagens por tipo, tags, pastas, total de itens e bytes usados em `Assets`;
  - `refreshLibrary()` atualiza itens e dados da sidebar;
  - helpers para limpar/trocar filtros preservando o auto-lock de atividade.
- **Implementado em SwiftUI**:
  - sidebar real com "Todos", tipos, tags, pastas, contagens e armazenamento usado;
  - filtros combináveis por clique na sidebar;
  - barra de filtros ativos removíveis no detalhe da biblioteca;
  - header com busca e botão de nova captura usando SF Symbols.
- **Validação rodada**:
  - `swift run --disable-sandbox HypomnemataNativeChecks` — passou.
  - `swift build --disable-sandbox --product HypomnemataMacApp` — passou.
- **Status**: primeira rodada da Sprint 2 concluída. Próxima rodada: Sprint 2.3 — Lista/Grid e Detalhe Básico.

### 2026-04-25 — Sprint 2.3: Lista/Grid e Detalhe Básico
- **Implementado em `AppModel`**:
  - `LibraryViewMode` com modos `list` e `grid`;
  - `selectedItem` para abrir detalhe em sheet;
  - `openDetail(_:)`, `saveItem(...)` e `deleteItem(_:)`;
  - salvar item atualiza título, nota, texto e tags via `SQLiteItemRepository.patchItem`;
  - excluir item usa `deleteItems(ids:)`, limpa seleção e atualiza biblioteca/sidebar.
- **Implementado em SwiftUI**:
  - controle segmentado Lista/Grid no header;
  - `ItemListView` com linhas clicáveis;
  - `ItemGridView` com `LazyVGrid` adaptativo e cards compactos;
  - `ItemDetailSheet` editável com título, fonte read-only, tags, nota e texto;
  - delete individual com confirmação;
  - helpers visuais para ícone de tipo, tags e título de fallback.
- **Checks ampliados**:
  - `patchItem` atualiza título/nota/texto/tags;
  - FTS5 reflete edição;
  - delete individual remove item, atualiza contagens por tipo, tags e total.
- **Validação rodada**:
  - `swift run --disable-sandbox HypomnemataNativeChecks` — passou.
  - `swift build --disable-sandbox --product HypomnemataMacApp` — passou.
- **Status**: segunda rodada da Sprint 2 concluída. Próxima rodada: Sprint 2.4 — Captura CRUD completa e assets criptografados.

### 2026-04-25 — Sprint 2.4: Captura CRUD completa e assets criptografados
- **Implementado em `SQLiteItemRepository`**:
  - `insertAsset(_:)` grava `AssetRecord` na tabela `assets`;
  - `assets(forItemID:)` lista assets por item para detalhe/delete;
  - assets seguem `ON DELETE CASCADE` no banco quando o item é removido.
- **Implementado em `EncryptedAssetStore`**:
  - `remove(record:)` remove arquivo criptografado físico do diretório `Assets`.
- **Implementado em `AppModel`**:
  - captura de arquivo lê `CaptureDraft.fileURL`, infere tipo pelo `CapturePlanner`, cria item, criptografa arquivo com AES-GCM e registra o asset no banco;
  - título de arquivo usa o nome do arquivo sem extensão quando o usuário não preenche título;
  - leitura de arquivo usa `startAccessingSecurityScopedResource()` quando o macOS fornecer URL security-scoped;
  - falha ao registrar asset remove o arquivo criptografado recém-criado e remove o item criado;
  - delete individual agora busca assets do item e remove os arquivos criptografados físicos após deletar o registro do item.
- **Implementado em SwiftUI**:
  - `CaptureSheet` agora tem abas URL, Arquivo e Texto;
  - aba Arquivo usa `fileImporter` com `UTType.item`, mostra o nome selecionado e salva via fluxo criptografado;
  - botão salvar valida URL, arquivo ou texto conforme aba ativa.
- **Checks ampliados**:
  - asset criptografado é registrado em `assets`;
  - conteúdo em disco é diferente do plaintext;
  - asset registrado é lido de volta pelo `EncryptedAssetStore`;
  - `remove(record:)` torna o asset físico ilegível.
- **Validação rodada**:
  - `swift run --disable-sandbox HypomnemataNativeChecks` — passou.
  - `swift build --disable-sandbox --product HypomnemataMacApp` — passou.
- **Status**: terceira rodada da Sprint 2 concluída. Próxima rodada: Sprint 2.5 — Seleção em lote, delete em lote e performance.

### 2026-04-25 — Sprint 2.5: seleção em lote, delete em lote e performance
- **Implementado em `SQLiteItemRepository`**:
  - `assets(forItemIDs:)` lista assets de múltiplos itens em uma query, usado antes de delete em lote.
- **Implementado em `AppModel`**:
  - `selectionMode`, `selectedItemIDs` e `selectedItemCount`;
  - `toggleSelectionMode()`, `toggleItemSelection(_:)`, `selectVisibleItems()`, `clearSelection()`;
  - `deleteSelectedItems()` usa um fluxo único de delete em lote;
  - delete em lote coleta assets antes de remover os itens, apaga os registros via `deleteItems(ids:)` e remove os arquivos criptografados físicos no `EncryptedAssetStore`;
  - seleção é limpa/prunada após refresh, troca de filtros e delete.
- **Implementado em SwiftUI**:
  - botão "Selecionar" no header;
  - indicadores de seleção em lista e grid;
  - highlight visual para itens selecionados;
  - toolbar inferior com contagem, selecionar visíveis, limpar e excluir;
  - confirmação antes de excluir itens selecionados.
- **Checks ampliados**:
  - `assets(forItemIDs:)` retorna assets esperados;
  - delete em lote remove registros e arquivos criptografados físicos;
  - cenário sintético com 10k itens inseridos em transação valida listagem, busca FTS5 e delete em lote com limites de tempo conservadores.
- **Validação rodada**:
  - `swift run --disable-sandbox HypomnemataNativeChecks` — passou.
  - `swift build --disable-sandbox --product HypomnemataMacApp` — passou.
- **Status**: Sprint 2 concluída. Próxima etapa: Sprint 3 — Captura Nativa.

### 2026-04-25 — Sprint 3.1: captura interna validada
- **Implementado em `HypomnemataIngestion`**:
  - `CaptureValidationError`, com mensagens legíveis para entrada ausente, múltiplas origens, URL inválida e arquivo não local;
  - `CapturePlanner.validate(_:)`, que normaliza URL/título/nota/texto/tags, rejeita captura ambígua e exige URL `http://` ou `https://` com domínio;
  - `CapturePlanner.validateAndPlan(_:)`, usado pelo app antes de criar item e registrar jobs planejados em `metadataJSON`.
- **Implementado em `AppModel`**:
  - `createCapture(_:)` agora retorna mensagem de erro em vez de jogar o app para `.failed` em erro recuperável de captura;
  - captura bem-sucedida continua criando item, registrando asset criptografado quando houver arquivo, fechando a sheet e atualizando biblioteca/sidebar;
  - erros de validação, leitura de arquivo ou gravação de asset ficam no fluxo de captura sem bloquear o vault.
- **Implementado em SwiftUI**:
  - `CaptureSheet` mostra erro inline;
  - falha do `fileImporter` aparece na própria sheet;
  - trocar de aba limpa erro antigo.
- **Checks ampliados**:
  - valida normalização de URL/título/nota/tags;
  - valida planejamento de URL de vídeo, PDF por arquivo e texto solto;
  - rejeita URL sem `http/https`, captura vazia e captura com múltiplas origens.
- **Validação rodada**:
  - `swift run --disable-sandbox HypomnemataNativeChecks` — passou.
  - `swift build --disable-sandbox --product HypomnemataMacApp` — passou.
- **Status**: Sprint 3.1 concluída. Próxima rodada: Sprint 3.2 — criar registros reais em `jobs` após captura.

### 2026-04-25 — Sprint 3.2: registros reais em `jobs` após captura
- **Implementado em `SQLiteItemRepository`**:
  - `insertJobs(_:)` grava uma lista de `Job` na tabela `jobs`;
  - `jobs(forItemID:)` lista jobs de um item em ordem estável por `created_at` e `id`;
  - mapeamento `Row -> Job` para leitura do status, payload e erro.
- **Implementado em `AppModel`**:
  - captura bem-sucedida não grava mais `planned_jobs` em `metadataJSON`;
  - depois de criar o item e, quando houver arquivo, registrar o asset criptografado, o app cria jobs reais com `status = pending`;
  - payload dos jobs inclui `source_url` para capturas por URL e `asset_id` para capturas de arquivo.
- **Checks ampliados**:
  - inserção e leitura de jobs pendentes;
  - preservação de `payload_json`;
  - cascade delete: apagar item remove seus jobs.
- **Validação rodada**:
  - `swift run --disable-sandbox HypomnemataNativeChecks` — passou.
  - `swift build --disable-sandbox --product HypomnemataMacApp` — passou.
- **Status**: Sprint 3.2 concluída. Próxima rodada: Sprint 3.3 — estado de erro recuperável em jobs sem perder item.

### 2026-04-25 — Sprint 3.3: erro recuperável em jobs e entrada externa
- **Implementado em `DependencyDoctor` / `JobDependencyResolver`**:
  - `DependencyDoctor.status(for:)` permite consultar uma dependência específica;
  - `JobDependencyResolver` mapeia jobs para binários externos: `scrapeArticle` → `trafilatura`, `downloadMedia` → `yt-dlp`, `generateThumbnail` → `ffmpeg`;
  - jobs que dependem de binário ausente são criados com `status = failed` e erro acionável com o comando `brew install ...`;
  - `runOCR`, `summarize` e `autotag` não falham por dependência local nesse estágio.
- **Implementado em `SQLiteItemRepository`**:
  - `updateJobStatus(id:status:error:)` atualiza status/erro sem remover item;
  - checks validam job `failed` com mensagem de dependência e preservação de cascade delete.
- **Implementado em `AppModel` / SwiftUI / AppKit**:
  - `createCapture(_:)` sempre preserva o item capturado e registra jobs pendentes ou falhos conforme dependências locais;
  - `CaptureSheet` aceita prefill para capturas externas;
  - `onOpenURL` recebe `http/https` diretos e `hypomnemata://capture?url=...` ou `hypomnemata://capture?text=...`;
  - `CaptureServicesProvider` registra provider AppKit para receber texto/URL via macOS Services pasteboard e abrir a sheet de captura preenchida.
- **Nota de empacotamento**:
  - o handler de Services existe no alvo SwiftPM; para aparecer no menu Share/Services de um `.app` distribuível ainda será necessário incluir a declaração `NSServices` no Info.plist na etapa de empacotamento/release.
- **Validação rodada**:
  - `swift run --disable-sandbox HypomnemataNativeChecks` — passou.
  - `swift build --disable-sandbox --product HypomnemataMacApp` — passou.
- **Status**: Sprint 3 funcionalmente concluída no app nativo. Próxima etapa: Sprint 4 — Organização e Zettelkasten.

### 2026-04-25 — Sprint 4.1: contratos de organização e Zettelkasten
- **Implementado em `SQLiteItemRepository`**:
  - operações completas de pasta para a próxima UI: `folders(forItemID:)`, `renameFolder(id:name:)`, `deleteFolder(id:)` e `removeItems(_:fromFolder:)`;
  - `DataError.folderNotFound` para rename de pasta inexistente;
  - leitura de links e backlinks como `ItemSummary` via `linkedItems(from:)` e `backlinks(to:)`;
  - links continuam sincronizados automaticamente ao criar/editar item a partir de `note` + `bodyText` com sintaxe `[[uuid|título]]`;
  - links/backlinks retornam título atual do item alvo/origem, então renomear item linkado não congela display antigo.
- **Checks ampliados**:
  - renomear pasta, remover/adicionar item em pasta, listar pastas de item e excluir pasta;
  - criar link em nota, ler links e backlinks, renomear alvo e confirmar título atualizado;
  - excluir item alvo remove relações por cascade e deixa links/backlinks vazios.
- **Validação rodada**:
  - `swift run --disable-sandbox HypomnemataNativeChecks` — passou.
  - `swift build --disable-sandbox --product HypomnemataMacApp` — passou.
- **Status**: Sprint 4.1 concluída. Próxima rodada: Sprint 4.2 — UI de pastas e operações.

### 2026-04-25 — Sprint 4.2: UI de pastas e operações
- **Implementado em `AppModel`**:
  - wrappers de UI para `createFolder`, `renameFolder`, `deleteFolder`, `addSelectedItems(to:)`, `foldersForItem(_:)`, `addItem(_:to:)` e `removeItem(_:from:)`;
  - operações atualizam sidebar/biblioteca e preservam auto-lock de atividade.
- **Implementado em SwiftUI**:
  - seção "Pastas" sempre visível na sidebar, com botão `+` para criar pasta;
  - menu contextual de pasta com "Renomear" e "Excluir";
  - sheets reutilizáveis `FolderNameSheet` e `FolderPickerSheet`;
  - toolbar de seleção ganhou "Adicionar à pasta", com criação de pasta inline quando necessário;
  - detalhe do item mostra chips de pastas, permite adicionar a pasta e remover item de uma pasta;
  - `FlowLayout` simples para chips de pasta no detalhe.
- **Validação rodada**:
  - `swift build --disable-sandbox --product HypomnemataMacApp` — passou.
  - `swift run --disable-sandbox HypomnemataNativeChecks` — passou.
- **Status**: Sprint 4.2 concluída. Próxima rodada: Sprint 4.3 — links clicáveis/autocomplete básico e backlinks no detalhe.

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

### 2026-04-21 — Legendas de vídeo do YouTube (Onda 2, item 7 revisitado)
- Download de legenda separado do vídeo em dois passos: (1) yt-dlp baixa o vídeo sem flags de legenda; (2) segunda chamada com `skip_download=True` tenta legenda em `["pt", "pt-BR"]`. Se falhar (HTTP 429, sem legenda), o vídeo já está salvo — não interrompe o download.
- **Bug corrigido**: flags de legenda na mesma chamada do vídeo causavam abort em HTTP 429 do YouTube.
- Legenda vira `body_text` (preferida sobre descrição para busca FTS5); descrição vai para `meta_json["description"]`. `meta_json["subtitle_lang"]` guarda o idioma detectado.
- Frontend: collapsible "Legenda (pt)" ou "Descrição do vídeo" no DetailModal conforme disponibilidade.

### 2026-04-21 — Polimento da IA: auto-resumo, indicador de loading e thumbnail no modal

- **Auto-resumo ao capturar**: após scraping de artigo ou download de vídeo com legenda, `article.py` e `ytdlp.py` chamam `summarize_sync()` (versão síncrona do `llm.py`) no mesmo thread. Falha silenciosa se MLX-LM não estiver rodando.
- **`ai_status = "pending"`**: antes de chamar o LLM, o backend seta `meta_json["ai_status"] = "pending"` e faz commit. Remove a chave no `finally` após concluir (com ou sem erro). Isso permite o frontend saber que o resumo está sendo gerado.
- **Polling no DetailModal**: o `useEffect` de polling agora também ativa quando `meta_json["ai_status"] === "pending"` — não só `download_status === "pending"`. Fica checando a cada 5s até o resumo chegar.
- **Indicador visual**: botão mostra "IA processando..." e fica desabilitado; box pulsante "▌ Gerando resumo com IA..." aparece na seção IA enquanto `ai_status` está pending.
- **Erros do LLM em amber**: quando LLM não está rodando e usuário clica "Resumir", o texto `[Erro: ...]` que vinha como texto de resumo agora aparece como badge amber com mensagem legível.
- **Poster do vídeo no modal**: `<video>` no DetailModal recebe `poster={api.assetUrl(thumbnailPath)}` extraído de `meta_json.thumbnail_path`. Corrige bug onde o modal mostrava frame aleatório em vez do thumbnail ao abrir o item.

### 2026-04-21 — MLX-LM em vez de Ollama para IA local
- **Problema**: Ollama com qwen2.5:7b (4.7 GB) travou o MacBook Air M2 8GB.
- **Tentativas**: Gemma 4 via Ollama = 7.2 GB (muito grande); Gemma 4 E2B via Ollama não tem Q4_0 disponível.
- **Solução**: MLX-LM com `mlx-community/gemma-4-e2b-it-4bit` = 1.3 GB (formato MLX nativo Apple Silicon). 40–87% mais rápido que Ollama/llama.cpp. Expõe `/v1/chat/completions` (OpenAI-compatible) na porta 8080.
- **Autenticação HuggingFace**: modelo é Apache 2.0 mas exige login HF. `brew install hf && hf auth login`.
- **Config**: `HYPO_LLM_URL=http://localhost:8080`, `HYPO_LLM_MODEL=mlx-community/gemma-4-e2b-it-4bit`. Para Ollama basta trocar a URL para `http://localhost:11434`.
- **Mac Mini M4 16GB**: pode usar `mlx-community/gemma-4-e4b-it-4bit` (~2.5 GB, mais qualidade) via `.env`.

### 2026-04-21 — IA: resumo streaming + auto-tagging (Onda 3, itens 9 e 10)
- **`llm.py`**: cliente agnóstico de provider. `stream_summary()` usa SSE streaming (`data: ...` chunks). `get_autotags()` retorna lista de tags via chamada não-streaming. `max_tokens`: 4096 para resumo, 1024 para tags (sem limite artificial — é local).
- **Rotas**: `POST /items/{id}/summarize` → `StreamingResponse` text/plain; salva resumo em `meta_json["summary"]` ao terminar. `POST /items/{id}/autotag` → `{"tags": [...]}`.
- **Frontend**: seção "IA" no painel direito do DetailModal (visível quando item tem conteúdo). Botão "Resumir" mostra texto aparecendo token a token com cursor piscante. Botão "Sugerir tags" retorna chips clicáveis (+ individual ou "Adicionar todas"). Resumo persiste ao reabrir modal via `meta_json["summary"]`.
- **Bug corrigido**: `max_tokens` não definido → MLX-LM usava padrão de 256 tokens → resumos cortados no meio da frase.

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

### Aprovadas (ainda não implementadas)

### 2026-04-22 — Backup Incremental para iCloud

**Mecanismo**: `rsync -a --delete <data_dir>/ <backup_dir>/` — copia só o que mudou, remove o que foi deletado. Antes do rsync faz `PRAGMA wal_checkpoint(TRUNCATE)` para garantir consistência do `.db`.

**Config**: `HYPO_BACKUP_DIR` no `backend/.env`. Caminho configurado: `~/Library/Mobile Documents/com~apple~CloudDocs/Minhas pastas/backup-hypomnemata`.

**Backend**:
- `config.py`: campo `backup_dir: Path | None`
- `backup.py`: `run_backup()` — checkpoint WAL + subprocess rsync. Levanta `RuntimeError` com mensagem legível em falha.
- `routes/system.py`: `POST /system/backup` (retorna `{ok, message}`, erro 503 em falha) + `GET /system/backup/status` (retorna se está configurado)
- `main.py`: dispara `run_backup()` em background no startup se `backup_dir` configurado. Falha silenciosa (não bloqueia servidor).

**Frontend** (`Sidebar.tsx`):
- Botão de sync (ícone de setas circulares) ao lado do "Exportar ZIP" no footer
- Estados: `idle` / `running` (spinner) / `ok` (✓ verde por 3s) / `error` (⚠ vermelho)
- Desabilitado e tooltip explicativo quando `HYPO_BACKUP_DIR` não configurado
- Horário da última sync salvo no `localStorage` e exibido no tooltip

### 2026-04-22 — Pastas (Coleções)

**Modelo**: many-to-many — um item pode estar em nenhuma, uma ou várias pastas.

**Backend:**
- `models.py`: tabelas `Folder (id, name, created_at)` e `FolderItem (folder_id, item_id, added_at)` com `ON DELETE CASCADE`
- `routes/folders.py`: `GET /folders`, `POST /folders`, `PATCH /folders/{id}`, `DELETE /folders/{id}`, `POST /folders/{id}/items {item_ids:[]}`, `DELETE /folders/{id}/items/{item_id}`
- `routes/items.py`: `GET /items?folder=<id>` (filtro novo) + `GET /items/{id}/folders` (pastas de um item)
- As tabelas são criadas via `Base.metadata.create_all` no startup — sem migration manual

**Frontend:**
- `api.ts`: `listFolders`, `createFolder`, `renameFolder`, `deleteFolder`, `addItemsToFolder`, `removeItemFromFolder`, `getItemFolders`; `listItems` aceita `folder?`
- `Sidebar.tsx`: seção "Pastas" abaixo de Etiquetas; botão `+` inline para criar; renomear via clique no lápis (hover); excluir via ×; drop target HTML5 (recebe drag de cards, destaca com anel âmbar); badge de contagem por pasta
- `Library.tsx`: estados `activeFolder`, `selectionMode`, `selectedItems: Set<string>`, `draggingItemId`; botão de modo seleção no header; Esc para sair do modo
- `Card.tsx`: `draggable={true}` — `onDragStart` injeta `item_id` no dataTransfer; checkbox visível quando `selectionMode` ativo (destaque visual quando selecionado)
- `SelectionToolbar.tsx` (novo): toolbar fixo na base da tela quando há itens selecionados — "Adicionar à pasta" (dropdown com lista + criar nova inline), "Excluir selecionados", "Cancelar"
- `DetailModal.tsx`: campo "Pastas" no painel direito (abaixo de Fonte) — chips removíveis, botão `+` com dropdown para adicionar

### 2026-04-22 — Refinamento do DetailModal

**Motivação**: painel direito estava poluído com dados internos (OCR, legendas) e com UX confusa (dois botões de IA, tags manuais).

**Mudanças implementadas**:

**Removidos do painel direito:**
- Collapsible "Texto extraído" (OCR) — dado interno para FTS5 e chat, não para leitura
- Collapsible "Legenda (pt)" / "Descrição do vídeo" — mesma lógica
- Botão "Sugerir tags" e chips de sugestão — substituído por geração automática no backend

**Campo "Descrição" (substitui seção IA):**
- Posição: abaixo do Título, acima das Etiquetas
- Fonte: `meta_json["summary"]` — mesmo campo do auto-resumo
- Editável livremente pelo usuário
- Botão "Gerar com IA" aparece **apenas** se o campo estiver vazio E o item tiver conteúdo
- Link "× limpar" aparece **apenas** se o campo tiver conteúdo — limpa + marca dirty
- Erro do LLM: exibido no banner `err`, campo volta para vazio (botão reaparece)
- Streaming renderiza diretamente na textarea (não em painel separado)
- `save()` inclui `summary: description` → `PATCH /items/{id}` → persiste em `meta_json["summary"]`

**Nova ordem dos campos:**
Título → Descrição → Etiquetas → Nota pessoal → Fonte

**Tags automáticas na captura:**
- `llm.py`: `get_autotags_sync()` — versão síncrona de `get_autotags()` para uso em workers (httpx síncrono, falha silenciosa)
- `crud.py`: `set_item_tags_sync(db_sync, item_id, names)` — versão síncrona de `set_item_tags` para uso em workers com Session síncrona
- `article.py`: chama `get_autotags_sync()` após scraping + resumo; salva tags no banco com `set_item_tags_sync()`
- `ytdlp.py`: chama `get_autotags_sync()` após download (incluindo vídeos sem legenda — usa título quando body_text indisponível); salva com `set_item_tags_sync()`
- Regra: tags geradas uma vez na captura. Se o usuário apagar tudo e salvar, ficam vazias — sem regeneração automática, sem botão

**Schema:** `ItemPatch` ganhou campo `summary: str | None`. PATCH handler atualiza `meta_json["summary"]` ao receber esse campo.

### 2026-04-22 — Chat com Documento (conversa persistente)

**Funcionalidade**: em qualquer item com `body_text` suficiente (≥ 300 chars — artigos, vídeos com legenda, PDFs com OCR), aparece um ícone de chat bubble no header do painel direito do DetailModal. Ao clicar, o painel direito é substituído temporariamente pela interface de chat; clicar novamente volta para notas/tags/IA. O histórico da conversa persiste indefinidamente no banco.

**Implementação**:

- **Backend** (`llm.py`): nova função `stream_chat(title, body_text, messages)`. Monta um system prompt com o conteúdo do item (até 6000 chars) e a instrução de responder só com base no conteúdo. Inclui o histórico completo de mensagens como contexto multi-turn. Streaming SSE idêntico ao `stream_summary`.

- **Backend** (`routes/items.py`): `POST /items/{id}/chat`. Recebe `{ messages: [{role, content}] }` (histórico completo até e incluindo a última mensagem do usuário). Após o streaming terminar, salva o histórico completo + resposta do assistente em `meta_json["chat_history"]` (mesmo padrão de persistência do `summary`). Erros de LLM chegam como texto na stream (não levantam exceção HTTP) para não interromper o streaming já iniciado.

- **Frontend** (`api.ts`): `chatStream(id, messages, onChunk)` — mesmo padrão do `summarizeStream`.

- **Frontend** (`DetailModal.tsx`):
  - `chatMode: boolean` — alterna o painel direito entre notas e chat.
  - `chatMessages` — estado local; inicializado a partir de `meta_json.chat_history` ao abrir o modal. Se houver histórico salvo, o modal abre já em modo chat.
  - `streamingMsg` — texto parcial da resposta em andamento, exibido como bolha em construção com cursor `▌`.
  - Auto-scroll via `messagesEndRef` a cada nova mensagem ou chunk.
  - Input: `Enter` envia, `Shift+Enter` seria nova linha (padrão esperado). Desabilitado durante `chatBusy`.
  - Erros do LLM aparecem como bolha âmbar (mesmo padrão do resto do app).
  - Ícone de chat bubble só aparece quando `body_text.length >= 300` — itens sem conteúdo suficiente não exibem o botão.
  - O histórico é salvo após cada turno completo (não em tempo real durante streaming) para evitar escritas parciais no banco.

**Persistência**: `meta_json["chat_history"]` — array de `{role: "user"|"assistant", content: string}`. Sobrescreve a cada novo turno (acumula). Sobrevive a fechar o modal, fechar o browser e reiniciar o backend. Não há limite de tamanho por ora.

### 2026-04-22 — Conexão de Ideias (Zettelkasten / Links)
- **Proposta**: Mencionar itens diretamente no texto das notas com `[[nome]]`, com IDs únicos por trás para que renomear um item atualize todas as referências automaticamente.
- **Decisão**: Aprovada e **implementada**.
- **Implementação**:
  - `models.py`: tabela `item_links (source_id, target_id)` com `ON DELETE CASCADE`.
  - `crud.py`: `sync_item_links()` — varre `note` e `body_text` via Regex, extrai `[[uuid|display]]` e recria os relacionamentos.
  - `routes/items.py`: `PATCH /items/{id}` chama `sync_item_links()` antes de commitar. Rotas `POST /items/{id}/links` e `DELETE /items/{id}/links/{target_id}` mantidas para futura API direta.
  - `NoteEditor.tsx`: modo Leitura (renderiza título atualizado em âmbar, clicável) e Edição (usa `react-mentions` com portal no `body` para autocomplete acima de modais).
  - `webapp/src/index.css`: estilos do `react-mentions` integrados ao design system.
  - `react-mentions` + `@types/react-mentions` adicionados ao frontend.
- **Formato gravado**: `[[550e8400-e29b-41d4-a716-446655440000|Nome do Item]]` — o UUID é permanente; o display é cache.
- **Bugs corrigidos**: portal z-index via `style` inline; dropdown cortado pelo `overflow:hidden` do modal; `handleClickOutside` fechando antes da seleção via verificação do elemento `.mentions-editor__suggestions`; largura do dropdown via `ResizeObserver`.

### 2026-04-21 — Ações em Lote e Pastas
- **Proposta**: Adicionar checkboxes na listagem para deleções e tags em lote, e a capacidade de organizar itens em pastas/listas.
- **Decisão**: Aprovada e **implementada** (2026-04-22).
- **Motivo**: Organização de grandes volumes de itens.

### 2026-04-21 — Visão de Linha do Tempo (Timeline)
- **Proposta**: Uma visualização alternativa que agrupa os cards por cabeçalhos temporais dinâmicos ("Hoje", "Semana Passada", "Março de 2026").
- **Decisão**: Aprovada.
- **Motivo**: Auxilia na recuperação temporal de itens.

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
- Plano (cópia em cache do Codex): `~/.Codex/plans/vc-deve-escrever-um-jazzy-blum.md`
