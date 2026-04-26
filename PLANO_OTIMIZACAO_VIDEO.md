# PLANO — Otimização de vídeo sob demanda

> **Convenção**: este documento é spec viva. Eu (Claude) atualizo conforme avanço; Codex implementa cada sprint. Sprints só podem rodar em ordem. Cada sprint tem critérios de aceite verificáveis.
> **Status global**: 📝 não iniciado · 🚧 em progresso · ✅ entregue · 🛑 bloqueado
> **Última atualização**: 2026-04-26 (Sprint 1 entregue)

---

## Decisões fechadas (alinhamento com usuário, 2026-04-26)

| # | Decisão | Origem |
|---|---|---|
| D1 | Escopo: `kind=.video` **e** vídeos de tweets (`kind=.tweet` cujo asset principal é vídeo). Áudio fica de fora. | usuário |
| D2 | Re-otimização não permitida. Após sucesso, botão desabilita permanentemente. | usuário |
| D3 | Mostrar comparação "antes X MB → depois Y MB (-Z%)" como confirmação. | usuário |
| D4 | Se output ≥ original: **descartar** output, manter original, mostrar "já está otimizado". Marcar como otimizado mesmo assim (D2 vale). | usuário |
| D5 | Barra de progresso real, parseando `out_time_ms / duration` do `ffmpeg -progress pipe:1`. | recomendação aceita |
| D6 | Botão de cancelar durante a conversão. `SIGTERM` no processo + descarte do temp parcial. | usuário |
| D7 | Asset criptografado: decrypt → temp → ffmpeg → temp output → re-encrypt → substitui `AssetRecord` (mesmo `id`, novo `encryptedPath`/`byteCount`) → apaga blob antigo → invalida cache de preview. | recomendação aceita |
| D8 | Integrar como `JobKind.optimizeVideo` no sistema de jobs existente. | recomendação aceita |
| D9 | Item permanece editável durante otimização (nota, tags). Só o botão de otimizar e o asset ficam travados. | recomendação aceita |
| D10 | Crash/desligar no meio: temp files órfãos limpos no startup; original nunca é tocado até a substituição atômica final. | recomendação aceita |

### Comando de referência (usuário)

```bash
ffmpeg -i input.mp4 -vcodec libx264 -crf 28 -preset slow -c:a aac -b:a 128k output.mp4
```

Esse é o comando-base. Vamos parametrizar `crf=28`, `preset=slow`, `audio_bitrate=128k` como constantes do código (não exposto ao usuário no MVP).

---

## Modelo de dados

### Novo `JobKind`
- `optimizeVideo` adicionado a `JobKind` em `HypomnemataCore/Models.swift`.
- Diferente dos outros jobs (que rodam automaticamente), este é **disparado por ação manual** (botão na UI). Mas reusa a infra: `Job` row, `JobStatus`, painel de status, retry on failure.

### `AssetRecord` — flag de otimização
- Novo campo: `optimizedAt: String?` (ISO timestamp). `nil` = nunca otimizado; `not nil` = já otimizado nessa data.
- Migration: `ALTER TABLE assets ADD COLUMN optimized_at TEXT` (não-destrutiva, default `NULL`).
- Lógica de "botão habilitado" no UI = `record.optimizedAt == nil && isVideoAsset(record)`.

### `Item.metadataJSON` — registro de tamanho original (D3)
- Antes de iniciar a otimização, salvamos `metadataJSON["video_original_size_bytes"] = <bytes>` para conseguir mostrar a comparação depois (após substituição, o `AssetRecord.byteCount` reflete só o novo tamanho).
- Persistente para histórico ("este vídeo foi otimizado: era 240MB, agora 78MB").

---

## Sprints

### Sprint 1 — Núcleo: pipeline ffmpeg + parser de progresso ✅
**Objetivo**: módulo Swift puro que recebe URL de input, URL de output, e callback de progresso. Roda ffmpeg, parseia stderr, reporta progresso, retorna sucesso/falha. Sem integração com vault/UI/jobs ainda — testável isoladamente.

**Entregas**:
- Novo arquivo `native/Sources/HypomnemataIngestion/VideoOptimizer.swift`:
  - `protocol VideoOptimizer { func optimize(input: URL, output: URL, progress: (Double) -> Void, isCancelled: () -> Bool) async throws -> VideoOptimizationResult }`.
  - `struct VideoOptimizationResult { let outputBytes: Int64; let durationSeconds: Double }`.
  - `struct FFmpegVideoOptimizer: VideoOptimizer` — implementação real.
  - Args: `["-i", input, "-vcodec", "libx264", "-crf", "28", "-preset", "slow", "-c:a", "aac", "-b:a", "128k", "-progress", "pipe:1", "-nostats", "-y", output]`.
  - **Duração**: pré-roda `ffprobe -show_entries format=duration -of csv=p=0 input` (1 chamada, rápido) para ter o total. Sem isso, progresso não tem denominador.
  - **Parser de progresso**: lê `pipe:1` linha-a-linha; quando bate `out_time_ms=<valor>`, calcula `Double(value) / 1_000_000 / totalDuration`, clampa em [0, 1], chama `progress(percent)`.
  - **Cancel**: `isCancelled()` polled a cada update; se `true`, `SIGTERM` no `Process`, aguarda exit, deleta `output`, throw `VideoOptimizationError.cancelled`.
  - Erros: `binaryNotFound`, `inputNotFound`, `ffprobeFailed`, `ffmpegFailed(exitCode, stderr)`, `cancelled`.

**Critérios de aceite** (Codex):
- Build compila.
- Teste em `HypomnemataNativeChecks/main.swift`: pega um `.mp4` pequeno de fixture (criar com ffmpeg numa rotina de setup do check, ou cachear binário pequeno em `tests/fixtures/`), roda otimização, verifica que output existe, é menor (ou pelo menos válido), tem duração próxima do input.
- Teste de cancelamento: roda em vídeo médio (~30s), seta `isCancelled = true` após 200ms, verifica que processo termina e output é deletado.
- Não toca em vault, DB ou UI.

---

### Sprint 2 — Integração: vault, AssetRecord, persistência 📝
**Objetivo**: orquestrar o pipeline completo para um item já existente: decrypt asset → otimizar → re-encrypt → substituir record. Sem UI ainda — exposto via API interna em `AppModel` ou serviço dedicado, testável headless.

**Entregas**:
- Migration: `ALTER TABLE assets ADD COLUMN optimized_at TEXT` em `HypomnemataData/Migrations.swift` (ou onde estiver) com try/catch para idempotência.
- Atualizar `AssetRecord` em `Models.swift` com `optimizedAt: String?`.
- Atualizar `AssetRepository` (queries SELECT/INSERT/UPDATE) para ler/escrever a coluna.
- Novo método em `EncryptedAssetStore` (ou serviço novo `VideoOptimizationService`):
  ```swift
  func optimizeVideoAsset(record: AssetRecord, optimizer: VideoOptimizer, progress: (Double) -> Void, isCancelled: () -> Bool) async throws -> OptimizeOutcome
  ```
- Pipeline:
  1. Validar: é vídeo, ainda não otimizado.
  2. `decryptToTemporaryFile(record)` → `inputURL`.
  3. Antes da conversão: ler `byteCount` original, salvar em `Item.metadataJSON["video_original_size_bytes"]` via repository.
  4. Criar `outputURL` em diretório temp (`FileManager.default.temporaryDirectory.appendingPathComponent("hypomnemata-optimize-\(uuid).mp4")`).
  5. `optimizer.optimize(...)`.
  6. **D4**: comparar `outputBytes` vs `record.byteCount`. Se `outputBytes >= record.byteCount`:
     - Deletar `outputURL`.
     - Setar `optimizedAt = now` (D2 — botão fica desabilitado mesmo assim).
     - Não trocar o blob criptografado.
     - Retornar `.alreadyOptimized(originalBytes: record.byteCount)`.
  7. Caso normal: re-encrypt o `outputURL` num novo `encryptedPath`. Atualizar `AssetRecord` (mesmo `id`, novo `encryptedPath`, `byteCount = outputBytes`, `optimizedAt = now`). Apagar blob criptografado antigo. Apagar `outputURL` e `inputURL` temp.
  8. Invalidar `assetPreviews` cache do item (para próximo open re-decrypt).
  9. Retornar `.optimized(originalBytes, newBytes)`.
- **Atomicidade**: a troca do `encryptedPath` precisa ser feita com cuidado. Sequência segura:
  1. Escrever novo blob em `encryptedPath_new`.
  2. UPDATE row do AssetRecord para `encryptedPath_new`.
  3. Apagar `encryptedPath_old`.
  Se crash entre (1) e (2): blob órfão em disco, recuperável por janitor (Sprint 4).
  Se crash entre (2) e (3): blob órfão, mesma situação.
  Nunca há janela em que o item fica sem asset.
- **Cleanup de temp**: `defer` para deletar `inputURL` e `outputURL` mesmo em erro.

**Critérios de aceite**:
- Build compila, migration roda em DB existente sem perder dados.
- Teste em `HypomnemataNativeChecks`: cria item com asset de vídeo (fixture), chama `optimizeVideoAsset`, verifica que (a) `optimizedAt` não é nil, (b) `byteCount` mudou (ou não, no caso D4), (c) decrypt do novo asset abre arquivo válido (ffprobe retorna duration), (d) blob antigo foi deletado.
- Teste de erro: ffmpeg falha → `optimizedAt` continua nil, asset não muda, temp files limpos.

---

### Sprint 3 — UI: botão, modal de progresso, integração com Job system 📝
**Objetivo**: tornar a feature acessível pelo usuário no DetailModal. Status visível, cancel funcional, comparação após sucesso.

**Entregas**:
- Adicionar `case optimizeVideo` em `JobKind` (`Models.swift`).
- Atualizar `JobAutomation.run(_:on:)` em `HypomnemataAI/JobAutomation.swift` para suportar `optimizeVideo`:
  - Recebe `progress` callback adicional (ou propaga via novo mecanismo — ver nota abaixo).
  - **Nota arquitetural**: `JobAutomation` atual é stateless e não emite progresso. Para esta feature precisamos de progresso ao vivo. Opções:
    - (a) Adicionar callback `(Double) -> Void` no `run()` — invasivo, muda assinatura.
    - (b) Criar um canal lateral: `JobProgressBroadcaster` (actor) que o `VideoOptimizer` atualiza e a UI observa via `AsyncStream`.
  - **Decisão preliminar**: (b) — menos invasivo. Pode mudar durante implementação; se mudar, atualizo este plano.
- `RootView.swift` — DetailModal de vídeo:
  - Novo botão "Otimizar vídeo" abaixo/ao lado do player. Visível só quando: `kind ∈ {.video, .tweet com video}` E `record.optimizedAt == nil`.
  - Clicou → entra no estado "otimizando":
    - Botão vira "Cancelar".
    - Barra de progresso 0–100% com label "Otimizando vídeo... 42%".
    - Resto do modal continua editável (D9).
  - Sucesso → toast/banner "Vídeo otimizado: 240 MB → 78 MB (-67%)" (D3). Botão desaparece (`optimizedAt` agora setado).
  - D4 (output ≥ input) → toast "Este vídeo já está bem otimizado, mantido o original (240 MB)". Botão desaparece.
  - Falha → toast vermelho "Erro ao otimizar: <mensagem>". Botão volta ao estado "Otimizar vídeo" (pode tentar de novo, já que `optimizedAt` segue nil).
  - Cancel → botão volta ao estado "Otimizar vídeo".
- Estado vive em `AppModel`: `@Published var optimizationState: [String: OptimizationState]` (chave = `itemID`). `OptimizationState = .idle | .running(progress: Double, cancelToken: CancelToken) | .succeeded(beforeBytes, afterBytes) | .alreadyOptimized(bytes) | .failed(message)`.
- Persiste durante a sessão (não em DB) — se usuário fecha modal, otimização continua em background; ao reabrir vê o progresso atualizado. Ao reabrir o app, jobs em running viram failed (Sprint 4 cuida disso).

**Critérios de aceite**:
- Build do app macOS roda; abrindo um item vídeo, botão aparece.
- Clicar inicia otimização real; barra avança; ao terminar mostra comparação.
- Cancel para o ffmpeg, deleta temp, libera UI.
- Fechar e reabrir o modal durante a otimização: progresso continua.
- Item já otimizado: botão não aparece.
- Editar nota/tags durante otimização funciona.

---

### Sprint 4 — Robustez: crash recovery, janitor, polimento 📝
**Objetivo**: cobrir os caminhos de erro/borda restantes, deixar a feature pronta para uso real.

**Entregas**:
- **Crash recovery (D10)**:
  - No startup do app (`AppModel.boot()` ou equivalente), rodar `cleanupOrphanOptimizationTempFiles()`:
    - Varre `FileManager.default.temporaryDirectory` por arquivos `hypomnemata-optimize-*.mp4`, deleta.
    - Varre `Job` rows com `kind=optimizeVideo, status=running` e marca como `failed` com mensagem "App reiniciado durante a otimização".
- **Janitor de blobs órfãos**:
  - Função `findOrphanEncryptedBlobs()` em `EncryptedAssetStore`: lista todos os arquivos no diretório de blobs, cruza com `AssetRecord.encryptedPath`, retorna os que não estão referenciados.
  - Roda no startup, deleta órfãos > 1h de idade (segurança contra race com escrita em andamento).
- **Validação extra**:
  - Antes de iniciar otimização, checar espaço em disco livre. Se < 2x tamanho do vídeo (input descriptografado + output esperado + folga), abortar com mensagem clara.
  - Verificar `which ffmpeg` e `which ffprobe` na inicialização da feature; se faltar, botão fica desabilitado com tooltip "Instale ffmpeg via Homebrew para usar esta funcionalidade" (já é dep listada em CLAUDE.md, mas defensivo).
- **Telemetria interna**: log estruturado de `optimizeVideo` (item_id, original_bytes, new_bytes, duration_seconds, ffmpeg_seconds, ratio).
- **Update CLAUDE.md**: adicionar seção "Decisões posteriores (2026-04-26) — Otimização de vídeo sob demanda" com resumo curto e ponteiro para este plano.
- **Update AGENTS.md / native/README.md** se houver instruções de DX afetadas.

**Critérios de aceite**:
- Matar o app durante uma otimização (kill -9) e reabrir: job aparece como failed, temp files sumiram, item segue intacto.
- Disco quase cheio: feature aborta com mensagem antes de começar.
- ffmpeg removido do PATH: botão desabilitado com tooltip.
- Janitor remove blobs órfãos antigos sem tocar nos atuais.

---

## Riscos e mitigações

| Risco | Mitigação |
|---|---|
| ffmpeg lento em vídeo longo (1h+ pode levar 30min com `preset=slow`) | Barra de progresso + cancel. Não é crítico — usuário sabe que está rodando. |
| Re-encrypt de vídeo grande aloca memória do tamanho do arquivo | `EncryptedAssetStore` atual usa `Data(contentsOf:)` (load all in memory). Vídeos > 1GB podem dar problema em Mac de 8GB. **Decisão**: aceitar limite atual no MVP; revisar se virar problema. |
| Crash entre escrever novo blob e UPDATE da row | Janitor (Sprint 4) limpa órfãos > 1h. Item nunca fica sem asset porque UPDATE só roda após escrita bem-sucedida. |
| Codex implementa errado ou muda assinatura prevista | Eu (Claude) reviso cada PR antes de marcar sprint como ✅. Atualizo este plano se algo mudar. |

---

## Dúvidas em aberto / sinalizar antes de implementar

Nenhuma no momento. Se surgir durante a implementação (especialmente sobre o canal de progresso, Sprint 3), atualizo este plano e te aviso antes de seguir.

---

## Histórico de atualizações

- **2026-04-26**: criação. Decisões D1–D10 fechadas com usuário. Plano com 4 sprints definido. Aguardando início da Sprint 1 (Codex).
- **2026-04-26**: Sprint 1 entregue. `FFmpegVideoOptimizer` criado com `ffprobe`, `ffmpeg -progress pipe:1`, parser de `out_time_ms` e cancelamento por `SIGTERM`; checks reais com fixture MP4, validação por `ffprobe` e cancelamento passaram.
