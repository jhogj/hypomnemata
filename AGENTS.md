# AGENTS.md — Memória viva do Hypomnemata

> **Primeira ação em toda sessão nova nesta área: ler este arquivo inteiro.**
> Ele diz onde paramos, o que foi decidido, o que está pendente e o que já quebrou.

---

## Protocolo

- **Plano geral**: ver `PLANO.md` (app legado) e `PLAN-completo.md` (rewrite nativo).
- **Ideias novas**: antes de implementar, registrar aqui (aprovada ou rejeitada, com motivo).
- **Decisões que divergem do plano**: entram aqui datadas. Não reescrever o plano silenciosamente.
- **Bugs**: seção própria, com repro e hipótese.
- **Formato**: leve, datado (`YYYY-MM-DD`), sem cerimônia.
- **Rewrite nativo — micro-passos**: implementar o recorte, atualizar docs, validar build/checks, reportar ao usuário e parar. Exceção em 2026-04-25: usuário pediu explicitamente fechar a sprint inteira.
- **Sem contorno silencioso**: se faltar instalação, permissão ou configuração, parar e informar o comando exato.

---

## Status atual

- **App legado** (FastAPI/React): Ondas 1, 2, 3 entregues. Onda 4 adiada. Ver `CLAUDE.md` para detalhes.
- **Rewrite nativo**: Sprints 0–7 entregues, incluindo o bloco de ingestão reaberto da Sprint 6: 6.4 (`scrapeArticle`), 6.5 (`downloadMedia`) e 6.6 (`generateThumbnail`/tweets).
- **Última sessão**: 2026-04-25 — Sprint 6.6: vídeos baixados agora geram thumbnail criptografada automaticamente; tweets por URL criam `downloadMedia` + `generateThumbnail`; `generateThumbnail` usa `GalleryDLThumbnailFetcher` com `gallery-dl` e fallback oEmbed (`publish.twitter.com/oembed`) para fotos. Checks cobrem gallery-dl, fallback oEmbed, fetcher ausente e planejamento de tweet.
- **Próxima tarefa**: Sprint 8 — backup, exportação e restore do app nativo.

### Comandos (nativo)

```
cd native
CLANG_MODULE_CACHE_PATH=/tmp/hypo-clang-cache SWIFTPM_HOME=/tmp/hypo-swiftpm-cache swift run --disable-sandbox HypomnemataNativeChecks
CLANG_MODULE_CACHE_PATH=/tmp/hypo-clang-cache SWIFTPM_HOME=/tmp/hypo-swiftpm-cache swift build --disable-sandbox --product HypomnemataMacApp
```

---

## Histórico de sprints (nativo)

| Sprint | Entregou |
|---|---|
| 0 | Fundamento: projeto SwiftPM, módulos, schema SQLite, migrations GRDB, `DependencyDoctor` |
| 1 | Vault: SQLCipher real, chave de assets no banco, cache temporário, auto-lock (15min + sleep), rekey |
| 2 | Biblioteca: sidebar com filtros, lista/grid, detalhe editável, captura de arquivo criptografado, seleção/delete em lote (10k itens) |
| 3 | Captura: validação, jobs reais (`status = pending/failed`), erros recuperáveis, `hypomnemata://` URL scheme + AppKit Services |
| 4 | Organização: pastas many-to-many, Zettelkasten (`[[uuid|título]]`), autocomplete de links, backlinks no detalhe |
| 5 | Mídia: previews descriptografados (imagem/PDF/vídeo), thumbnails AES-GCM, play inline com continuidade de timestamp, OCR nativo Vision/PDFKit |
| 6.1 | IA infraestrutura: `LLMClient` (protocolo), `OpenAICompatibleClient`, `LLMConfiguration`, erros recuperáveis, checks com `FakeLLMClient` |
| 6.2 | IA funcional: resumo (`summarize`), autotags conservadoras (preserva tags existentes), campo editável no detalhe |
| 6.3 | Automação: `JobAutomation` roda `summarize`/`autotag` em background pós-captura; autotag automático só se `tags.isEmpty`; retry manual de jobs falhos; seção "Tarefas" no detalhe com status colorido |
| 7.1 | Settings de IA: `LLMSettingsStore` no vault SQLCipher; `LLMConfiguration.resolve(overrides:env:)` em camadas (vault > env > default); UI em "IA local" com salvar/limpar e validação |
| 7.2 | Chat com documento: `ItemChatService` (gate de 300 chars + system prompt em pt), métodos `chatHistory/appendChatMessage/clearChatHistory` no repositório, `AppModel.sendChatMessage` com streaming, painel de chat no detalhe com bubbles, cursor piscante e limpar conversa |
| 7.3 | Resumo em streaming: `ItemAIService.streamSummary` (mesmo prompt do `summarize`, mas via `streamChat`), `AppModel.streamSummary` com `onChunk`, campo "Resumo" do detalhe é zerado e preenchido em tempo real conforme os chunks chegam |
| 6.4 | Runner de `scrapeArticle`: subprocess `trafilatura` (JSON), fallback WKWebView para SPA, metadata persistida e hero image criptografada |
| 6.5 | Runner de `downloadMedia`: `yt-dlp` + `ffmpeg` para merge, legendas pt/en, asset criptografado via `EncryptedAssetStore`, polling/erros recuperáveis |
| 6.6 | Runner de `generateThumbnail`: thumbnail automática de mídia baixada; tweets com foto via `gallery-dl` + fallback oEmbed |
| **8+** | **Próximo**: backup, exportação e restore |

---

## Decisões arquiteturais (nativo)

### 2026-04-25 — Rewrite nativo macOS
- **Decisão**: nova trilha `native/` — Swift/SwiftUI, macOS 14+, Apple Silicon, módulos `Core/Data/Media/Ingestion/AI/Backup/App`.
- **Motivo**: produto vira app leve de macOS; FastAPI/React passam a ser referência funcional, não destino final.
- **Extensão Chrome/MV3**: descartada do produto novo. Captura via app interno + Share/Services nativos.
- **Dados antigos**: sem migração no primeiro release nativo.

### 2026-04-25 — SQLCipher e chave de assets no vault
- **Decisão**: GRDB vendorizado em `native/Vendor/GRDBSQLCipher` com manifest SwiftPM próprio para linkar SQLCipher. Sem fallback plaintext — produção falha fechada sem SQLCipher.
- **Motivo**: dependência direta em `groue/GRDB.swift` linka SQLite do sistema e não criptografa.
- **Chave de assets**: 32 bytes AES via `SecRandomCopyBytes`, persistida em `settings.asset_key_v1` como Base64 dentro do vault. Estável entre sessões, protegida pela senha do SQLCipher.
- **Lock**: `fail-closed` — descarta `database`, `repository`, `assetStore`, chaves e seleção mesmo se alguma etapa de limpeza falhar.

### 2026-04-25 — Jobs como registros reais
- **Decisão**: captura cria registros na tabela `jobs` com `status = pending` (ou `failed` quando binário ausente). Nenhum planejamento em `metadataJSON`.
- **Motivo**: jobs em JSON não oferecem rastreamento, retry ou cascade de delete. Binários ausentes ficam com `brew install ...` acionável na mensagem de erro.

### 2026-04-25 — OCR síncrono na captura
- **Decisão**: OCR roda sincronamente em `createCapture`, não em job separado. Limita PDFs a 12 páginas.
- **Motivo**: Vision/PDFKit é nativo e rápido; job assíncrono adicionaria complexidade sem ganho perceptível.
- **Fallback**: PDF digital via `PDFDocument.string`; PDF escaneado por página renderizada com PDFKit + Vision.

### 2026-04-25 — IA via LLMClient (Sprint 6)
- **Decisão**: `LLMClient` é protocolo. `OpenAICompatibleClient` consome `/v1/chat/completions`. Configuração via `HYPO_LLM_URL`, `HYPO_LLM_MODEL`, `HYPO_LLM_CONTEXT_LIMIT`.
- **Motivo**: mesmo design do app legado; permite trocar provider sem mudar lógica de produto.
- **Falha de IA**: indisponibilidade do servidor não quebra captura — vira job recuperável.

### 2026-04-25 — Settings de IA persistidas no vault (Sprint 7.1)
- **Decisão**: `LLMSettingsStore` grava overrides em chaves `llm_url_v1`/`llm_model_v1`/`llm_context_limit_v1` na tabela `settings` do vault SQLCipher.
- **Motivo**: settings sensíveis (URL interna, modelo) ficam criptografadas dentro do vault e acompanham backup/restore. Sem arquivos plaintext em `~/Library/Preferences`.
- **Prioridade**: `LLMConfiguration.resolve(overrides:env:)` resolve campo por campo — vault > env > default. Vault é fonte de verdade do app; env vira fallback global do shell.
- **Validação**: `saveLLMSettings` chama `resolve(...)` antes de gravar; URL/modelo/limite inválidos não são persistidos.
- **UI**: nova seção "IA local" em `SettingsView` com placeholders mostrando o valor atualmente em uso (env ou default), botões salvar/limpar overrides, e linha de resumo "Em uso: <url> · <modelo> · <limite>".

### 2026-04-25 — Reabrir Sprint 6 para ingestão web (6.4–6.6 antes da 8)
- **Contexto**: o `PLAN-completo.md` original definia Sprint 6 como "Ingestão Web, Vídeos E Tweets" (trafilatura + yt-dlp + gallery-dl + WKWebView fallback). Na implementação, Sprint 6 foi inteiramente reaproveitada para IA (6.1 infra LLM, 6.2 resumo/autotag funcional, 6.3 `JobAutomation`), e o trabalho de ingestão foi adiado com a nota "aguardando o runner de Sprint 7+". Sprint 7 (7.1/7.2/7.3) cuidou só de IA — então o runner nunca foi escrito.
- **Sintoma confirmado em 2026-04-25**: capturar URL de artigo gera job `scrapeArticle` que fica `pending` para sempre; capturar URL de vídeo do YouTube gera `downloadMedia` `pending` e o detalhe mostra "Este item não tem vídeo local para reproduzir". Texto colado/arquivos locais funcionam porque dependem só de `bodyText`/asset já no banco.
- **Causa raíz no código**: `Sources/HypomnemataAI/JobAutomation.swift` lança `unsupportedJobKind` para `scrapeArticle`/`downloadMedia`/`generateThumbnail`/`runOCR` (`runOCR` na real roda síncrono na captura, então tudo bem; os outros três é que ficam órfãos).
- **Decisão**: reabrir Sprint 6 antes da 8 (backup), em três sub-sprints isoladas:
  - **6.4** — runner de `scrapeArticle`: subprocess `trafilatura --json --URL`, fallback `WKWebView` (renderiza JS, devolve HTML para `trafilatura --json`), hero image baixada, criptografada via `EncryptedAssetStore` e ligada como asset do item. Status amarrado ao job; erro recuperável quando rede/binário falham.
  - **6.5** — runner de `downloadMedia`: subprocess `yt-dlp` (merge via `ffmpeg`), legenda preferida pt/en (segunda chamada com `skip_download` para não abortar em 429), arquivo final movido cripto para `Assets/`. UI atualiza assim que o job vira `done`.
  - **6.6** — runner de `generateThumbnail` para mídia baixada e fotos de tweets: `yt-dlp` info-thumb + ffmpeg fallback para vídeos; `gallery-dl` para tweets com foto + fallback oEmbed (`publish.twitter.com/oembed`). Thumb sai encriptada e alimenta lista/grid e detalhe.
- **Sprint 8 (backup) só depois disso**: ingestão é coração da captura; sem ela o nativo não substitui o legado, então prioridade > backup.
- **Não-objetivo**: não vamos migrar dados antigos do app legado nesse bloco (continua fora do v1).

### 2026-04-25 — Runner de artigo entregue (Sprint 6.4)
- **Decisão**: `scrapeArticle` saiu de `unsupportedJobKind` e entrou em `JobAutomation.supportedKinds`; sem scraper configurado falha com `missingExecutor`, e item sem URL falha com `missingSourceURL`.
- **Implementação**: `TrafilaturaArticleScraper` roda `trafilatura --json --URL <url>`, parseia `title/text/description/author/sitename/date/image`, baixa hero image quando houver bytes válidos e usa `WKWebViewPageRenderer` como fallback quando o texto extraído fica abaixo de 200 caracteres.
- **App**: `AppModel` instancia `JobAutomation` com `TrafilaturaArticleScraper(renderer: WKWebViewPageRenderer())`; `.articleScraped` atualiza título quando o item não tem título manual, `bodyText`, `meta_json` e grava a hero image criptografada como asset `heroImage`.
- **Validação**: `HypomnemataNativeChecks` cobre runner configurado, runner ausente, URL vazia, JSON do trafilatura, falha de subprocesso, conteúdo curto e fallback via HTML renderizado. `swift build --product HypomnemataMacApp` e `swift run HypomnemataNativeChecks` passaram em 2026-04-25.
- **Pendente depois da 6.4**: 6.5 (`downloadMedia`) e 6.6 (`generateThumbnail` de mídia/tweets) ainda não tinham executor. A 6.5 foi entregue na seção seguinte.

### 2026-04-25 — Runner de vídeo entregue (Sprint 6.5)
- **Decisão**: `downloadMedia` entrou em `JobAutomation.supportedKinds`; sem downloader configurado falha com `missingExecutor`, e item sem URL falha com `missingSourceURL`.
- **Implementação**: `YTDLPMediaDownloader` roda `yt-dlp --dump-json` para título/duração/webpage, depois baixa o vídeo com `--merge-output-format mp4`. Legendas rodam em segunda chamada best-effort (`--skip-download`, `--write-subs`, `--write-auto-subs`, `--sub-langs pt.*,pt,en.*,en`) para que erro de legenda/rate limit não derrube o download do vídeo. O maior arquivo de vídeo gerado vira o resultado principal; `.vtt/.srt/.ass` viram legendas quando existirem.
- **App**: `AppModel` instancia `YTDLPMediaDownloader`; `.mediaDownloaded` grava vídeo como asset criptografado `.original`, legendas como `.subtitle`, preserva título manual quando existe e persiste `webpage_url`/`duration_seconds` em `meta_json`.
- **Dependências**: `downloadMedia` agora exige `yt-dlp` e `ffmpeg`; captura sem algum deles continua criando job `failed` recuperável com comando Homebrew.
- **Validação**: `HypomnemataNativeChecks` cobre runner configurado, runner ausente, URL vazia, subprocess fake criando vídeo+legenda, falha de subprocesso e download sem arquivo final. `swift build --product HypomnemataMacApp` e `swift run HypomnemataNativeChecks` passaram em 2026-04-25.
- **Pendente**: 6.6 (`generateThumbnail` de mídia/tweets) ainda não tem executor.

### 2026-04-25 — Legendas não bloqueiam vídeo
- **Bug**: `yt-dlp` abortava `downloadMedia` quando a legenda em `en` ou `pt` falhava com HTTP 429, mesmo quando o vídeo podia baixar normalmente. A UI mostrava também "Falha recuperável de IA" para erro de ingestão.
- **Correção**: download de vídeo e download de legenda foram separados. A etapa de legenda é opcional e ignorada se falhar; vídeos em português/inglês continuam baixando mesmo sem legenda. `LLMRecoverableErrorMapper` agora rotula erros de `ArticleScrapeError`/`MediaDownloadError`/`RemoteThumbnailError` como "Falha recuperável de ingestão".
- **Validação**: check novo simula 429 apenas na chamada `--skip-download` de legenda e exige que o `.mp4` seja retornado sem legendas.

### 2026-04-25 — Crash do VideoPlayer SwiftUI
- **Bug**: após baixar vídeo e reabrir/salvar o item, o app abortava com `failed to demangle superclass of VideoPlayerView from mangled name 'So12AVPlayerViewC'` vindo de `_AVKit_SwiftUI`.
- **Hipótese**: bug/runtime mismatch do `VideoPlayer` SwiftUI no macOS 26.4.1 com o toolchain atual, disparado quando a UI renderiza preview inline/detalhe com vídeo local.
- **Correção**: remover uso de `VideoPlayer` SwiftUI e usar `AppKitVideoPlayer: NSViewRepresentable` em cima de `AVPlayerView` nos três previews de vídeo (lista, grid, detalhe). Mantém `AVPlayer`, controles e continuidade de timestamp.
- **Validação**: `swift build --product HypomnemataMacApp` e `swift run HypomnemataNativeChecks` passaram em 2026-04-25.

### 2026-04-25 — Runner de miniatura/tweet entregue (Sprint 6.6)
- **Decisão**: `generateThumbnail` entrou em `JobAutomation.supportedKinds`. Para tweets por URL, o plano de captura agora cria `downloadMedia` e `generateThumbnail`; assim tweet com vídeo tenta baixar vídeo, e tweet com foto ainda tem caminho por `gallery-dl`/oEmbed.
- **Implementação**: `GalleryDLThumbnailFetcher` roda `gallery-dl -D <temp> <url>` e usa a maior imagem baixada. Se `gallery-dl` falhar ou não gerar imagem, tenta `https://publish.twitter.com/oembed?omit_script=true&url=<tweet>` e baixa `thumbnail_url` ou o primeiro `img src` do HTML retornado.
- **App**: `.thumbnailFetched` grava a imagem original criptografada e gera asset `.thumbnail` com `NativeThumbnailGenerator`; se a imagem já estiver em formato pronto mas o gerador não suportar, grava a própria imagem como `.thumbnail`. `.mediaDownloaded` também chama `createThumbnailIfSupported` logo depois de salvar o vídeo original.
- **Dependências**: `generateThumbnail` exige `ffmpeg` e `gallery-dl`; falha de dependência continua sendo job recuperável. Para uploads locais, a geração síncrona anterior continua igual.
- **Validação**: `HypomnemataNativeChecks` cobre planejamento de tweet, `JobAutomation.canRun(.generateThumbnail)`, fetcher fake, `gallery-dl` fake gerando imagem, fallback oEmbed e build do app. `swift build --product HypomnemataMacApp` e `swift run HypomnemataNativeChecks` passaram em 2026-04-25.
- **Resultado**: bloco 6.4–6.6 fechado; próxima frente documentada é Sprint 8.

### 2026-04-26 — Mitigação P0 da revisão de ingestão
- **Bug**: runners de `trafilatura`, `yt-dlp` e `gallery-dl` drenavam `stdout` e `stderr` em sequência e usavam paths fixos em `/opt/homebrew/bin`, abrindo risco de deadlock em saída grande e quebrando Intel Macs/Homebrew em outro prefixo.
- **Correção**: novo `SubprocessRunner` em `HypomnemataIngestion` resolve executáveis pelo `PATH` (com fallback Homebrew/macOS) e lê `stdout`/`stderr` em paralelo. Defaults dos runners agora são `trafilatura`, `yt-dlp` e `gallery-dl`, não paths absolutos.
- **Bug**: `AppModel.runAutomatedJobs` criava `ItemAIService` antes de qualquer job; configuração inválida de LLM marcava também jobs de ingestão como falha de IA.
- **Correção**: `JobAutomation` aceita serviço de IA opcional; `summarize`/`autotag` ainda exigem LLM, mas `scrapeArticle`/`downloadMedia`/`generateThumbnail` rodam sem LLM. `AppModel` marca como falhos apenas os jobs de IA quando a configuração do provider quebra e continua os jobs de ingestão pendentes.
- **Validação**: `swift build --product HypomnemataMacApp` e `swift run HypomnemataNativeChecks` passaram em 2026-04-26. Checks novos cobrem resolução por `PATH`, executável ausente e job de ingestão rodando sem serviço LLM.

### 2026-04-26 — Mitigação P1 da revisão de ingestão
- **Bug**: falha parcial em `.mediaDownloaded`/`.thumbnailFetched` podia deixar rows em `assets` apontando para arquivos já removidos (ou assets intermediários vivos) quando uma etapa posterior falhava.
- **Correção**: `SQLiteItemRepository` ganhou `deleteAssets(ids:)`; `AppModel` mantém a lista de assets gravados durante aplicação de mídia/thumbnail e faz rollback best-effort de rows + arquivos criptografados em qualquer falha posterior. `createThumbnailIfSupported` agora retorna o `AssetRecord` criado para entrar no rollback do chamador.
- **Bug**: OCR roda síncrono na captura, mas quando `NativeOCRExtractor` retornava erro suportado/sem texto, o plano ainda criava `.runOCR` pendente; como `JobAutomation` não executa OCR, esse job ficava preso.
- **Correção**: captura com OCR planejado sempre consome `.runOCR` no caminho síncrono e insere o job já `done`, extraindo texto quando possível e nunca deixando pendência sem executor.
- **Validação**: `swift build --product HypomnemataMacApp` e `swift run HypomnemataNativeChecks` passaram em 2026-04-26. Checks cobrem remoção explícita de rows de asset para suportar rollback.

### 2026-04-26 — Mitigação P2 da revisão de ingestão
- **Tweets**: `downloadMedia` em tweet sem arquivo de vídeo agora vira `.skipped` quando o downloader termina sem mídia; `generateThumbnail` continua cobrindo foto remota. `applyRemoteThumbnailResult` não cria outra miniatura quando o item já tem thumbnail local, evitando duplicação após vídeo baixado.
- **oEmbed**: fallback de tweet passou a montar `publish.twitter.com/oembed` com `URLComponents`/`URLQueryItem`, preservando URLs com `?`, `&` e outros caracteres reservados.
- **Detalhe**: `ItemDetailSheet` agora mantém um snapshot base e só atualiza campos com mudanças de background quando não há edição local suja; assets/jobs/chat continuam recarregando.
- **Chave de assets**: `EncryptedAssetStore.generateKeyData()` virou `throws` e valida o retorno de `SecRandomCopyBytes`, alinhando a API pública ao caminho de produção do vault.
- **Validação**: `swift build --product HypomnemataMacApp` e `swift run HypomnemataNativeChecks` passaram em 2026-04-26. Checks cobrem tweet sem vídeo como skipped, query oEmbed com caracteres reservados e geração falhável de chave.

### 2026-04-26 — YouTube com áudio sem vídeo + extração de áudio
- **Bug**: URL de YouTube podia resultar em mídia sem faixa de vídeo porque `yt-dlp` escolhia formato sem `-f`; `--merge-output-format mp4` não força seleção de vídeo+áudio.
- **Correção**: `YTDLPMediaDownloader` agora usa modo explícito. Modo vídeo roda seletor estrito H.264/AAC (`bv*[vcodec^=avc1]+ba[ext=m4a]/b[vcodec^=avc1][acodec!=none]/b[ext=mp4][vcodec^=avc1]`) e `--merge-output-format mp4`, sem `--remux-video`. Isso evita salvar `.mp4` com VP9/AV1 que o AVPlayer toca só como áudio.
- **Funcionalidade**: novo `ItemKind.audio`; captura por URL ganhou toggle "Salvar mídia como áudio". Quando ativo, o item é planejado como áudio e o downloader usa `--extract-audio --audio-format m4a`, salvando asset original `audio/mp4`. Áudio aparece nos filtros e pode ser reproduzido pelo mesmo player AppKit.
- **Validação**: `swift build --product HypomnemataMacApp` e `swift run HypomnemataNativeChecks` passaram em 2026-04-26. Checks cobrem planejamento de áudio, argumentos de vídeo+áudio do YouTube, extração m4a e dispatch de `downloadMedia` em modo áudio.

### 2026-04-26 — Sidebar sem tags e rodapé compacto
- **Bug**: o rodapé da sidebar ficava alto demais e sobrepunha a lista de tags; o botão "Nova captura" também estava duplicado ali, apesar de já existir no cabeçalho da biblioteca.
- **Correção**: tags foram removidas da superfície visual por enquanto (filtro lateral, campos de captura/detalhe e chips em lista/grid), preservando os dados no modelo. O rodapé agora mostra só armazenamento usado e, abaixo, "Trocar senha" ao lado do ícone de bloqueio.

### 2026-04-26 — Armazenamento vivo e thumbnails do YouTube
- **UI**: o rodapé da sidebar centraliza o armazenamento usado e os controles do vault; o seletor lista/grid não mostra mais o texto "Visualização".
- **Armazenamento**: `AppModel` recalcula uso de assets após jobs de background e rollback/remoção de assets, não apenas quando a lista visível é recarregada.
- **YouTube**: `YTDLPMediaDownloader` lê a URL `thumbnail` do `yt-dlp --dump-json`, baixa a imagem e entrega junto do `MediaDownloadResult`; `AppModel` salva essa imagem como thumbnail do vídeo antes do fallback por frame local.

### 2026-04-26 — Limite 1080p para vídeos
- **Decisão**: downloads de vídeo via `yt-dlp` continuam restritos a H.264/AAC compatível com AVPlayer, mas agora também exigem `height<=1080` em todos os ramos do seletor. Isso evita arquivos 1440p/4K grandes demais.

### 2026-04-26 — Otimização de vídeo sob demanda Sprint 1
- **Decisão**: iniciar pelo caminho recomendado em `PLANO_OTIMIZACAO_VIDEO.md`: núcleo isolado antes de vault/DB/UI.
- **Implementação**: novo `FFmpegVideoOptimizer` em `HypomnemataIngestion` roda `ffprobe` para duração, depois `ffmpeg` com `libx264`, `crf=28`, `preset=slow`, AAC 128k e `-progress pipe:1`. O parser lê `out_time_ms`, clampa progresso em 0...1 e cancela com `Process.terminate()` quando o token externo sinaliza cancelamento.
- **Validação**: `HypomnemataNativeChecks` cria fixtures MP4 temporários com `ffmpeg`, otimiza um vídeo real, valida duração com `ffprobe` e cobre cancelamento com remoção do output parcial. `swift build --product HypomnemataMacApp` e `swift run HypomnemataNativeChecks` passaram em 2026-04-26.
- **Próximo passo**: Sprint 2 — integrar vault, `AssetRecord.optimizedAt`, migration e substituição segura do blob criptografado.

### 2026-04-26 — Otimização de vídeo sob demanda Sprint 2
- **Decisão**: integração headless ficou em `VideoOptimizationService` no módulo de dados, porque a orquestração precisa coordenar `ItemRepository`, `EncryptedAssetStore` e `VideoOptimizer`. `EncryptedAssetStore` ganhou só a escrita de replacement mantendo o mesmo `AssetRecord.id`.
- **Implementação**: migration `v2_asset_optimized_at`; `AssetRecord.optimizedAt`; `SQLiteItemRepository.updateAsset(_:)`; serviço `optimizeVideoAsset` faz decrypt temporário, salva `metadataJSON["video_original_size_bytes"]`, roda optimizer, aplica D4 quando o output não reduz, re-encripta output em novo blob, atualiza a row com mesmo id e remove o blob antigo após o UPDATE.
- **Validação**: checks cobrem otimização real de asset criptografado, decrypt/ffprobe do novo blob, remoção do blob antigo, metadata preservada com tamanho original, caminho D4 sem troca do blob e falha de optimizer sem alterar asset/`optimizedAt` nem deixar temp `hypomnemata-optimize-*`. `swift build --product HypomnemataMacApp` e `swift run HypomnemataNativeChecks` passaram em 2026-04-26.
- **Próximo passo**: Sprint 3 — expor na UI via ação manual, progresso/cancelamento e integração com jobs.
- **Notas para Sprint 3**: não precisa invalidar cache explicitamente porque `decryptToTemporaryFile` sempre re-descriptografa e sobrescreve o arquivo temporário. `isVideoAsset` do serviço cobre `mp4/mov/m4v`; suficiente para MVP porque downloads são forçados para MP4 H.264, mas uploads manuais `webm/mkv` podem exigir expansão futura. Concorrência simultânea no mesmo record será bloqueada pela UI/estado `running`, sem lock no serviço. `durationSeconds` do replacement usa a duração de input medida por `ffprobe`, equivalente ao output esperado.

### 2026-04-26 — Otimização de vídeo sob demanda Sprint 3
- **Decisão**: `optimizeVideo` é `JobKind` real, mas manual. Ele não entra em `runAutomatedJobs` pós-captura; botão/retry chamam `VideoOptimizationService` diretamente e atualizam o job row. Isso preserva a infra de jobs sem forçar `JobAutomation` a depender de Data/Media.
- **Progresso**: em vez de `JobProgressBroadcaster`, o canal lateral ficou em `AppModel.optimizationState[itemID]` com estados `running/succeeded/alreadyOptimized/failed`; é suficiente para a sheet fechar/reabrir e continuar mostrando progresso na sessão.
- **UI**: `ItemDetailSheet` mostra "Otimizar vídeo" para `.video` e `.tweet` com asset de vídeo original não otimizado; durante execução mostra barra e botão cancelar; sucesso mostra comparação `antes → depois (-%)`; D4 mostra "já está bem otimizado"; falha deixa o botão disponível novamente.
- **Validação**: `swift build --product HypomnemataMacApp` e `swift run HypomnemataNativeChecks` passaram em 2026-04-26. Checks atualizados para `JobAutomation.canRun(.optimizeVideo)` e dependência `ffprobe`.
- **Próximo passo**: Sprint 4 — recovery de crash, janitor de blobs órfãos, validação de espaço/deps na UI e logs.

### 2026-04-26 — Otimização de vídeo sob demanda Sprint 4
- **Recovery**: ao desbloquear o vault, `AppModel` remove arquivos temporários `hypomnemata-optimize-*`, marca jobs `optimizeVideo` que ficaram `running` como `failed` com "App reiniciado durante a otimização.", e roda janitor de blobs órfãos antigos.
- **Janitor**: `EncryptedAssetStore.findOrphanEncryptedBlobs(referencedPaths:olderThan:)` cruza arquivos `.hasset` no diretório de assets com `SQLiteItemRepository.allAssets()`. Só remove órfãos com mais de 1h para evitar corrida com escrita em andamento.
- **Performance de unlock**: janitor de blobs roda em `Task.detached(priority: .utility)` após o unlock; limpeza de temps e recovery de jobs continuam síncronos porque são rápidos.
- **Validação pré-execução**: antes de iniciar otimização, `AppModel` exige `ffmpeg`/`ffprobe` e espaço livre >= 2x o tamanho do vídeo. Sem dependência, o botão aparece desabilitado com tooltip "Instale ffmpeg via Homebrew para usar esta funcionalidade."
- **Checagens revisadas**: `record.byteCount` é tamanho plaintext, então `byteCount * 2` é a base correta para validar espaço. O janitor varre todos os `.hasset`, não só blobs de otimização; isso é intencional porque qualquer blob sem row em `assets` é órfão.
- **Log**: sucesso/D4 emite log estruturado `optimizeVideo` com `item_id`, bytes antes/depois, duração, tempo de ffmpeg e ratio.
- **Validação**: `swift build --product HypomnemataMacApp` e `swift run HypomnemataNativeChecks` passaram em 2026-04-26. Checks cobrem recovery de job running, `allAssets()` e janitor de órfãos antigos preservando órfãos recentes.
- **Resultado**: `PLANO_OTIMIZACAO_VIDEO.md` fechado nas quatro sprints.

### 2026-04-25 — Resumo em streaming na sheet de detalhe (Sprint 7.3)
- **Decisão**: `ItemAIService` ganha `streamSummary(context:)` que retorna `AsyncThrowingStream<String, Error>` reaproveitando exatamente os mesmos `summaryMessages(for:)` do `summarize` síncrono — só muda o transporte (`streamChat` no lugar de `complete`). Isso garante que o resumo gerado pelo botão e o resumo gerado pelos jobs de background convergem para o mesmo prompt.
- **Camada de app**: `AppModel.streamSummary(title:note:bodyText:onChunk:)` segue o mesmo desenho de `sendChatMessage` — recupera serviço, faz `for try await chunk in stream`, acumula localmente e devolve a string final consolidada (também trim/empty-check). Erros viram mensagem via `LLMRecoverableErrorMapper`. `JobAutomation` continua usando `summarize` síncrono — sem mudança de comportamento em jobs.
- **UI**: `ItemDetailSheet.generateSummary()` zera o `summary` antes de iniciar e cada `onChunk` faz `summary += chunk`. Quando o stream termina, a versão final consolidada (já trim) substitui o conteúdo. `ProgressView()` ao lado do botão "Gerar resumo" segue como indicador de atividade — o próprio campo em crescimento já comunica progresso.
- **Erro de stream vazio**: se o provider devolver string em branco a UI mostra "Resposta vazia do provider de IA." e o campo permanece zerado — não persistimos resumo vazio em cima de um valor anterior.

### 2026-04-25 — Chat persistente com documento (Sprint 7.2)
- **Decisão**: `ItemChatService` (módulo `HypomnemataAI`) monta system prompt em português que restringe a resposta ao conteúdo do item; histórico vai para a tabela `chat_messages` (já existente desde Sprint 0) via `appendChatMessage`/`chatHistory`/`clearChatHistory` no `ItemRepository`.
- **Gate de disponibilidade**: chat só aparece quando `bodyText` tem ≥ 300 caracteres (`ItemChatService.isAvailable(for:)`). `LLMClientError.emptyContent` é lançado para mensagem em branco ou item sem conteúdo suficiente — UI nem inicia o stream.
- **Streaming**: `AppModel.sendChatMessage(item:userContent:onChunk:)` resolve a configuração de IA pela mesma camada do Sprint 7.1 (`LLMConfiguration.resolve(overrides:env:)`), persiste a mensagem do usuário antes do stream e a resposta final só depois de coletada (resposta vazia vira erro recuperável e não polui o histórico).
- **UI**: botão de toggle no header do detalhe (visível só quando o chat está disponível); `ChatPanel` com bubbles distintas para usuário/assistente, cursor piscante durante streaming, scroll-to-end automático, confirmação de limpeza e desabilitação de envio enquanto há resposta em andamento. O botão "Salvar" some no modo chat para evitar gravar nota acidentalmente.
- **Cascade**: delete do item remove `chat_messages` via `ON DELETE CASCADE` (validado nos checks).

### 2026-04-25 — Automação de jobs (Sprint 6.3)
- **Decisão na época**: `JobAutomation` rodava apenas `summarize` e `autotag`. Isso foi superado pelas Sprints 6.4 e 6.5, que adicionaram runners para `scrapeArticle` e `downloadMedia`; `generateThumbnail` segue aguardando 6.6.
- **Dispatch**: após `createCapture`, `Task` em background processa jobs pendentes do item. Captura nunca é bloqueada.
- **Autotag conservador**: roda automaticamente só quando `item.tags.isEmpty`. Se já há tags manuais, vira `.skipped` com `status = done`. Botão manual no detalhe mantém comportamento de preservação (passa `existingTags`).
- **Retry**: incrementa `attempts`, marca `pending` e re-dispara. Sem limite de tentativas — usuário decide.
- **Concorrência**: `runningJobIDs: Set<String>` no `AppModel` evita dispatch duplicado do mesmo job.
- **UI**: seção "Tarefas" no detalhe lista cada job com status colorido (`pending`/`running`/`done`/`failed`), erro inline e botão "Tentar novamente". Polling de 1s enquanto há `pending`/`running`.

---

## Referências rápidas

- Memória do app legado: `CLAUDE.md`
- Plano aprovado (app legado): `PLANO.md`
- Plano nativo: `PLAN-completo.md`
- Status nativo detalhado + comandos: `native/README.md`
- Esboço técnico original: `descricao_hypomnemata.txt`
- Wireframes: `design/Hypomnemata Wireframe.html`
