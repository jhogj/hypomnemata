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
- **Rewrite nativo**: Sprints 0–6 + 7.1 + 7.2 concluídas em 2026-04-25.
- **Última sessão**: 2026-04-25 — Sprint 7.2: chat persistente com documento (tabela `chat_messages` + `ItemChatService` + UI no detalhe com streaming).
- **Próxima tarefa**: Sprint 7.3 — streaming do resumo na sheet de detalhe.

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
| **7.3** | **Próximo**: streaming do resumo na sheet de detalhe |

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

### 2026-04-25 — Chat persistente com documento (Sprint 7.2)
- **Decisão**: `ItemChatService` (módulo `HypomnemataAI`) monta system prompt em português que restringe a resposta ao conteúdo do item; histórico vai para a tabela `chat_messages` (já existente desde Sprint 0) via `appendChatMessage`/`chatHistory`/`clearChatHistory` no `ItemRepository`.
- **Gate de disponibilidade**: chat só aparece quando `bodyText` tem ≥ 300 caracteres (`ItemChatService.isAvailable(for:)`). `LLMClientError.emptyContent` é lançado para mensagem em branco ou item sem conteúdo suficiente — UI nem inicia o stream.
- **Streaming**: `AppModel.sendChatMessage(item:userContent:onChunk:)` resolve a configuração de IA pela mesma camada do Sprint 7.1 (`LLMConfiguration.resolve(overrides:env:)`), persiste a mensagem do usuário antes do stream e a resposta final só depois de coletada (resposta vazia vira erro recuperável e não polui o histórico).
- **UI**: botão de toggle no header do detalhe (visível só quando o chat está disponível); `ChatPanel` com bubbles distintas para usuário/assistente, cursor piscante durante streaming, scroll-to-end automático, confirmação de limpeza e desabilitação de envio enquanto há resposta em andamento. O botão "Salvar" some no modo chat para evitar gravar nota acidentalmente.
- **Cascade**: delete do item remove `chat_messages` via `ON DELETE CASCADE` (validado nos checks).

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
