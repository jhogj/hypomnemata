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
- **Rewrite nativo**: Sprints 0–6 concluídas em 2026-04-25.
- **Última sessão**: 2026-04-25 — Sprint 6.3: automação pós-captura de IA, retry de jobs, indicadores no detalhe.
- **Próxima tarefa**: Sprint 7 — runners reais para `scrapeArticle`/`downloadMedia`/`generateThumbnail` (subprocessos Homebrew) ou início da Sprint 8 (backup/restore).

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

### 2026-04-25 — Automação de jobs (Sprint 6.3)
- **Decisão**: `JobAutomation` roda apenas `summarize` e `autotag` por enquanto. `scrapeArticle`/`downloadMedia`/`generateThumbnail` continuam sendo criados como `pending` (ou `failed` se faltar binário) mas ficam aguardando o runner de Sprint 7+.
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
