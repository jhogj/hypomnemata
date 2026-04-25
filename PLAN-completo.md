# Plano De Rewrite Nativo Do Hypomnemata Para macOS

## Resumo

- Reescrever o Hypomnemata como **app nativo macOS em Swift/SwiftUI**, Apple Silicon, macOS 14+.
- Descartar totalmente a extensão Chrome/MV3. Captura será feita pelo app e por integração nativa de Share/Services do macOS.
- Começar com base limpa: **sem migração dos dados atuais** no primeiro release.
- Usar **SQLite + GRDB + SQLCipher + FTS5** como core local.
- Implementar senha com criptografia real: banco criptografado e assets criptografados em repouso.
- Manter IA via servidor local configurável OpenAI-compatible, sem empacotar modelo no app v1.
- Exigir dependências Homebrew para mídia/scraping: `ffmpeg`, `yt-dlp`, `gallery-dl`, `trafilatura`.

## Decisões Arquiteturais

- O novo app substitui `backend/` e `webapp/` por módulos Swift nativos. O backend FastAPI vira referência funcional, não runtime.
- `extension/` não será portada, mantida ou considerada no produto novo.
- A UI será SwiftUI, com AppKit apenas onde SwiftUI não entregar performance suficiente.
- Banco em `~/Library/Application Support/Hypomnemata/`, não mais `~/Hypomnemata/`.
- Dados principais:
  - `items`: tipo, URL, título, nota, texto extraído, resumo, timestamps, metadata JSON.
  - `assets`: múltiplos arquivos por item, role, MIME, tamanho, duração/dimensões, caminho criptografado.
  - `tags`, `item_tags`, `folders`, `folder_items`, `item_links`.
  - `chat_messages`, em tabela própria.
  - `jobs`, para OCR, scraping, download, thumbnails, IA e erros.
- Busca:
  - SQLite FTS5 sobre título, nota, texto extraído e resumo.
  - Busca case/diacritic-insensitive e prefix match como hoje.
- Segurança:
  - Primeiro uso cria vault com senha.
  - SQLCipher protege o banco.
  - Uma chave aleatória de assets fica guardada dentro do banco criptografado.
  - Assets são criptografados com AES-GCM via CryptoKit.
  - Lock descarta conexão do banco, chave de assets e arquivos temporários.
  - Touch ID pode ser opção depois da primeira senha, via Keychain/LocalAuthentication.
- Captura:
  - Modal interno com URL, arquivo e texto.
  - Share/Services do macOS envia URL/texto para uma janela rápida de captura.
  - Sem screenshot automático de página no v1.
- IA:
  - Configuração para `HYPO_LLM_URL` equivalente, via Settings.
  - Resumo, autotags e chat continuam, consumindo `/v1/chat/completions`.
  - Se servidor local estiver indisponível, UI mostra erro e mantém item salvo.
- Dependências:
  - App valida `ffmpeg`, `yt-dlp`, `gallery-dl`, `trafilatura`.
  - Não instala automaticamente; mostra comando Homebrew esperado.
  - OCR usa Vision/PDFKit nativo, sem Tesseract no v1.

## Sprints

### Sprint 0 — Fundamento Técnico

Entrega:
- Criar projeto macOS nativo com módulos `App`, `Core`, `Data`, `Media`, `Ingestion`, `AI`, `Backup`.
- Definir schema SQLite v1, migrations GRDB e contratos internos.
- Criar tela mínima de lançamento bloqueada por senha.
- Criar “Dependency Doctor” em Settings.

Como fazer:
- Configurar GRDB com SQLCipher e FTS5 habilitado.
- Criar abstrações `ItemRepository`, `AssetStore`, `JobQueue`, `SearchService`.
- Mapear tipos finais: `image`, `article`, `video`, `tweet`, `bookmark`, `note`, `pdf`.

Testar:
- App abre e cria vault novo.
- Banco não abre com `sqlite3` comum.
- FTS5 funciona em banco SQLCipher.
- Dependências ausentes aparecem como erro acionável.

### Sprint 1 — Vault, Senha E Storage Criptografado

Entrega:
- Fluxo completo de criar senha, desbloquear, bloquear e trocar senha.
- Storage criptografado para assets.
- Limpeza de cache temporário no lock/quit.

Como fazer:
- SQLCipher para banco.
- Asset key persistida dentro do banco criptografado.
- Arquivos descriptografados só para cache temporário quando PDFKit/AVPlayer exigirem arquivo.
- Lock automático após 15 minutos de inatividade e ao acordar de sleep.

Testar:
- Senha errada não abre vault.
- Troca de senha preserva itens.
- Assets no disco não são legíveis diretamente.
- Cache temporário some após lock.
- Crash/reopen não corrompe vault.

### Sprint 2 — Biblioteca Nativa

Entrega:
- Sidebar com tipos, tags, pastas, contagem e armazenamento usado.
- Lista e grid de itens.
- CRUD básico de nota, bookmark, arquivo e texto.
- Delete individual e em lote.
- Filtros por tipo, tag e pasta.

Como fazer:
- SwiftUI para shell principal.
- Lazy grids/listas para performance.
- Repositórios GRDB observáveis para atualizar UI sem polling HTTP.

Testar:
- Criar, editar, excluir e listar itens.
- 10k itens sintéticos com busca e scroll aceitáveis.
- Filtros combinados não quebram contagens.
- Delete remove vínculos, tags associadas e assets.

### Sprint 3 — Captura Nativa

Entrega:
- Janela de captura com abas URL, Arquivo e Texto.
- Integração Share/Services do macOS para receber URL/texto.
- Inferência de tipo por URL/extensão.
- Jobs criados automaticamente após captura.

Como fazer:
- URLs genéricas viram `article`.
- YouTube/Vimeo viram `video`.
- X/Twitter vira `tweet`.
- PDFs, imagens e vídeos por extensão viram seus tipos.
- Nenhuma dependência de extensão de navegador.

Testar:
- Capturar URL manual.
- Capturar URL via Share.
- Capturar arquivo PDF, imagem, vídeo e texto solto.
- Captura sem dependência instalada cria item e job com erro legível, sem perder dados.

### Sprint 4 — Organização E Zettelkasten

Entrega:
- Tags manuais.
- Pastas many-to-many.
- Seleção em lote.
- Links/backlinks via sintaxe `[[item-id|título]]`.
- Autocomplete de links nas notas.

Como fazer:
- Manter IDs UUIDv7 string.
- Atualizar `item_links` ao salvar nota/texto.
- Renderizar links com título atual do item.
- Backlinks aparecem no detalhe do item.

Testar:
- Criar links, renomear item linkado e ver título atualizado.
- Deletar item remove links/backlinks.
- Item pode estar em múltiplas pastas.
- Operações em lote não duplicam relações.

### Sprint 5 — Mídia, PDF, OCR E Thumbnails

Entrega:
- Preview de imagem, vídeo e PDF.
- Play inline de vídeo no grid/lista e continuidade no detalhe.
- Thumbnail de PDF e vídeo.
- OCR nativo de imagens e PDFs escaneados.

Como fazer:
- PDFKit para leitura e thumbnail de primeira página.
- AVFoundation para vídeo e thumbnails de uploads.
- Vision para OCR de imagem e páginas renderizadas de PDF.
- Texto OCR alimenta FTS e `body_text`.

Testar:
- PDF digital indexa texto.
- PDF escaneado usa OCR.
- Imagem com texto fica pesquisável.
- Vídeo toca no card e continua no detalhe.
- Thumbnails não colidem entre itens.

### Sprint 6 — Ingestão Web, Vídeos E Tweets

> **Nota de divergência (2026-04-25)**: a implementação real apropriou Sprint 6 para o trabalho de IA (6.1 infra LLM, 6.2 resumo/autotag funcional, 6.3 `JobAutomation`). O escopo original abaixo foi adiado e voltou ao plano como sub-sprints **6.4 (scrapeArticle)**, **6.5 (downloadMedia)** e **6.6 (generateThumbnail/tweet)**, a serem entregues antes da Sprint 8. Detalhes em `AGENTS.md` ("Reabrir Sprint 6 para ingestão web").

Entrega:
- Scraping de artigos com título, texto, autor, data, site e imagem principal.
- Download de vídeos/legendas via `yt-dlp`.
- Tweets com vídeo via `yt-dlp`.
- Tweets com fotos via `gallery-dl`, com fallback oEmbed.
- Jobs com status, logs resumidos e retry.

Como fazer:
- Usar `trafilatura --json --URL <url>` para extração primária.
- Para páginas JS, renderizar HTML com WKWebView e passar HTML ao `trafilatura`.
- Usar diretório temporário por job e mover resultado criptografado para AssetStore.
- `ffmpeg` fica como dependência validada para merge/processamento do `yt-dlp`.

Testar:
- Artigo comum extrai corpo e imagem.
- SPA renderizada extrai texto após WKWebView.
- YouTube baixa vídeo, legenda preferindo `pt`, depois `en`.
- Tweet com fotos cria múltiplos assets.
- Falha de rede/dependência deixa item recuperável e erro claro.

### Sprint 7 — IA Local

Entrega:
- Settings para URL/modelo local.
- Gerar resumo.
- Gerar tags automáticas após ingestão.
- Chat persistente com documento.
- Indicadores de job IA.

Como fazer:
- Cliente OpenAI-compatible streaming.
- Prompt equivalente ao atual, com limite de contexto configurado.
- Chat salvo em `chat_messages`, não em JSON solto.
- Auto-tags só rodam se item ainda não tiver tags manuais.

Testar:
- Servidor indisponível não quebra captura.
- Streaming aparece incrementalmente.
- Resumo persiste.
- Chat persiste entre reaberturas.
- Tags automáticas não sobrescrevem tags do usuário.

### Sprint 8 — Backup, Exportação E Restore Do Próprio App

Entrega:
- Exportar ZIP do vault criptografado.
- Backup incremental para pasta escolhida, incluindo iCloud Drive.
- Restore de backup criado pelo app novo.
- Tela de status de backup.

Como fazer:
- Antes do backup, executar checkpoint WAL.
- Copiar banco, WAL, SHM e assets criptografados.
- Manter sentinel `.hypomnemata-backup`.
- Não implementar importação do app antigo nesta fase.

Testar:
- Backup incremental copia só mudanças.
- Restore em instalação limpa abre com a mesma senha.
- Backup não roda em diretório não confirmado.
- ZIP exportado não expõe assets descriptografados.

### Sprint 9 — Estabilização E Release Interno

Entrega:
- App assinado/notarizado para distribuição interna.
- Testes automatizados e roteiro manual de QA.
- Documentação de instalação Homebrew.
- Orçamento de performance validado.

Critérios:
- Cold launch até tela bloqueada abaixo de 1s em Apple Silicon moderno.
- Abrir biblioteca vazia/desbloqueada abaixo de 1.5s.
- Idle sem jobs abaixo de 150MB.
- Busca em 10k itens abaixo de 100ms em cenário sintético.
- Nenhum asset sensível legível fora do app.

Testar:
- Regressão completa: nota, arquivo, artigo, vídeo, tweet, PDF, OCR, busca, tags, pastas, links, IA, backup.
- Testes de dependência ausente.
- Testes de lock/unlock/sleep.
- Testes de banco corrompido ou job interrompido.
- Testes UI com VoiceOver básico e navegação por teclado.

## Paralelização Para A Equipe

- Agente A: vault, SQLCipher, schema, repositories, FTS.
- Agente B: SwiftUI shell, biblioteca, detalhe, captura interna.
- Agente C: Media/OCR/PDF/vídeo/assets criptografados.
- Agente D: Ingestão web, subprocessos Homebrew, jobs e retries.
- Agente E: IA local, chat, resumo, autotags.
- Agente F: backup, restore, Dependency Doctor, QA e release.

## Fora Do Escopo Do Primeiro Release

- Extensão Chrome/MV3.
- Migração dos dados atuais.
- Screenshot automático de navegador.
- Empacotar modelo local de IA dentro do app.
- Cross-platform Windows/Linux.
- Multiusuário, conta online ou sincronização cloud real.

## Assunções Travadas

- Stack oficial: Swift nativo.
- Segurança: criptografia real, não apenas lock de UI.
- Compatibilidade: Apple Silicon, macOS 14+.
- Captura principal: app + Share/Services nativo.
- Dependências externas: exigidas via Homebrew.
- Primeiro release: paridade sólida antes de redesign visual.
- IA: servidor local configurável OpenAI-compatible.
- Dados antigos: não serão migrados no v1.

## Referências Técnicas

- SwiftUI: [Apple SwiftUI](https://developer.apple.com/documentation/SwiftUI)
- Keychain: [Apple Keychain Services](https://developer.apple.com/documentation/security/keychain-services)
- LocalAuthentication: [Apple LocalAuthentication](https://developer.apple.com/documentation/localauthentication/)
- Vision OCR: [Apple Vision RecognizeTextRequest](https://developer.apple.com/documentation/vision/recognizetextrequest)
- PDFKit: [Apple PDFKit](https://developer.apple.com/documentation/quartz/pdfkit)
- SQLite FTS5: [SQLite FTS5](https://sqlite.org/fts5.html)
- GRDB: [GRDB.swift](https://github.com/groue/GRDB.swift)
- SQLCipher: [SQLCipher](https://www.zetetic.net/sqlcipher/)
- Trafilatura CLI: [trafilatura command line](https://trafilatura.readthedocs.io/en/stable/usage-cli.html)
- Homebrew formulas: [yt-dlp](https://formulae.brew.sh/formula/yt-dlp), [gallery-dl](https://formulae.brew.sh/formula/gallery-dl), [trafilatura](https://formulae.brew.sh/formula/trafilatura)
