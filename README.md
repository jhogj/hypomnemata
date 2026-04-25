# Hypomnemata

Repositório local-first de mídia e ideias — captura de tweets, vídeos, artigos, prints e notas em um único lugar, sem depender de APIs externas.

Estado atual: o app legado FastAPI/React já passou das Ondas 1, 2 e 3; a trilha principal agora é o rewrite nativo em `native/`. No nativo, as Sprints 0, 1, 2, 3, 4, 5, 6.1 e 6.2 estão concluídas em 2026-04-25; próxima etapa: Sprint 6.3 — automação, reprocessamento e validação final de IA.

> **Antes de trabalhar nesta pasta**, leia `CLAUDE.md` — ele tem o status atual, decisões e próximos passos. O plano completo está em `PLANO.md`.
> Para o rewrite nativo, leia também `AGENTS.md` e `native/README.md`.

## Arquitetura

Três processos independentes:

- **backend/** — FastAPI em `127.0.0.1:8787` + SQLite com FTS5 em `~/Hypomnemata/hypomnemata.db` + assets em `~/Hypomnemata/assets/`.
- **webapp/** — React + Vite + Tailwind em `http://localhost:5173`. Proxy de `/api/*` para o backend.
- **extension/** — Chrome MV3 (manifest `commands` com ⌘⇧Y para captura direta).

## Pré-requisitos

- Python ≥ 3.12 e [uv](https://github.com/astral-sh/uv)
- Node ≥ 20 e **npm** (ou bun/pnpm se preferir — veja nota abaixo)
- Chrome ou Chromium para carregar a extensão em modo desenvolvedor

## Subir o backend

```bash
cd backend
uv sync
uv run uvicorn hypomnemata.main:app --host 127.0.0.1 --port 8787 --reload
```

Na primeira execução o backend cria `~/Hypomnemata/` (banco + pasta de assets). Para mudar o destino: `HYPO_DATA_DIR=/caminho uv run ...`.

Variáveis de ambiente (prefixo `HYPO_`):

| Variável | Default | O que faz |
|---|---|---|
| `HYPO_DATA_DIR` | `~/Hypomnemata` | raiz dos dados |
| `HYPO_MAX_ASSET_MB` | `100` | tamanho máximo por upload |
| `HYPO_HOST` / `HYPO_PORT` | `127.0.0.1` / `8787` | onde o uvicorn escuta |

Testes: `uv run pytest` (42 testes, todas as rotas cobertas + workers de OCR/download/IA + guard de path-traversal).

## Subir o webapp

```bash
cd webapp
npm install
npm run dev
```

Abra `http://localhost:5173`. O Vite faz proxy de `/api/*` → `127.0.0.1:8787`.

Build de produção: `npm run build` gera `dist/` estático.

## Carregar a extensão

```bash
cd extension
npm install
npm run build
```

Abra `chrome://extensions` → ative **Modo desenvolvedor** → **Carregar sem compactação** → selecione `extension/dist/`.

Depois de carregada:
- Clique no ícone para abrir o popup (tags, nota, botão "Capturar aba").
- Ou use o atalho **⌘⇧Y** em qualquer página — captura direta com badge de confirmação.
- Páginas `chrome://` e a Chrome Web Store são restringidas pelo próprio Chrome; a extensão não captura essas.

Para mudar o backend padrão da extensão (ex: rodar em outra porta), clique em "configurar backend" no popup.

## Verificação end-to-end

1. Backend no ar (`uv run uvicorn ...`).
2. Webapp aberto em `localhost:5173` — biblioteca vazia.
3. Extensão carregada em `chrome://extensions`.
4. Abrir uma página qualquer → clicar ícone → "Capturar aba" → badge ✓ no ícone.
5. Voltar ao webapp, recarregar → card aparece na masonry.
6. Clicar no card → modal com preview + nota editável + tags.
7. Buscar no topo → item filtrado por FTS5.
8. Excluir → card some e o arquivo em `~/Hypomnemata/assets/` é removido.
9. `GET http://127.0.0.1:8787/assets/../../etc/passwd` → 400/404 (path-traversal bloqueado).

## Notas

**Gerenciador de pacotes JS**: o projeto está preparado para bun (decisão 9 em `CLAUDE.md`), mas por ora foi validado com npm. Se você tem bun, `bun install && bun run dev` funciona sem mudanças — só apague `package-lock.json` antes.

**Busca**: FTS5 com `remove_diacritics 2` — "filosofia" casa com "filosófia". Tokens são tratados como prefixos (`arqui` acha "arquitetura").

**Privacidade**: tudo local. Backend escuta só em `127.0.0.1`. Sem telemetria, sem autenticação (usuário único).

## Estrutura

```
Hypomnemata/
├── CLAUDE.md              memória viva (app legado)
├── AGENTS.md              memória viva (rewrite nativo)
├── PLANO.md               plano aprovado (app legado)
├── PLAN-completo.md       plano do rewrite nativo
├── README.md              você está aqui
├── descricao_hypomnemata.txt  esboço técnico original
├── design/                wireframes (3 telas)
├── backend/               FastAPI + SQLite + FTS5
├── webapp/                React + Vite + Tailwind
├── extension/             Chrome MV3
└── native/                rewrite nativo Swift/SwiftUI (trilha principal)
```

## Estado atual

- **App legado** (FastAPI/React): Ondas 1, 2 e 3 entregues — captura, OCR, yt-dlp, scraping, IA local, chat, Zettelkasten, pastas, backup ZIP.
- **Rewrite nativo** (`native/`): Sprints 0–5 + 6.1 + 6.2 concluídas. Próxima: Sprint 6.3.
- **Onda 4** (busca semântica) adiada.

Ver `PLANO.md` e `PLAN-completo.md` para o roadmap detalhado.
