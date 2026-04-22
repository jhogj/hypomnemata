"""Cliente LLM via OpenAI-compatible /v1/chat/completions.

Compatível com MLX-LM (porta 8080), LM Studio (porta 1234) e Ollama (porta 11434).
Configure HYPO_LLM_URL e HYPO_LLM_MODEL para trocar de provider sem mexer no código.
"""
from __future__ import annotations

import json
import logging
from collections.abc import AsyncGenerator

import httpx

from .config import settings

log = logging.getLogger("hypomnemata.llm")

_SUMMARY_PROMPT = """\
Resume o seguinte conteúdo em português, de forma concisa e direta (3 a 5 frases). \
Não use bullet points. Escreva só o resumo, sem introdução nem explicação.

{content}

Resumo:"""

_AUTOTAG_PROMPT = """\
Sugira de 3 a 6 tags (palavras-chave) em português para categorizar o seguinte conteúdo. \
Responda APENAS com as tags separadas por vírgula, sem pontuação extra, sem numeração, sem explicação.

{content}

Tags:"""


def _build_content(title: str | None, body_text: str | None, max_chars: int = 4000) -> str | None:
    parts = []
    if title:
        parts.append(f"Título: {title}")
    if body_text:
        parts.append(body_text[:max_chars])
    return "\n\n".join(parts) if parts else None


async def stream_summary(
    title: str | None,
    body_text: str | None,
) -> AsyncGenerator[bytes, None]:
    content = _build_content(title, body_text)
    if not content:
        return
    messages = [{"role": "user", "content": _SUMMARY_PROMPT.format(content=content)}]
    timeout = httpx.Timeout(connect=5.0, read=None, write=10.0, pool=5.0)
    try:
        async with httpx.AsyncClient(timeout=timeout) as client:
            async with client.stream(
                "POST",
                f"{settings.llm_url}/v1/chat/completions",
                json={"model": settings.llm_model, "messages": messages, "stream": True, "max_tokens": 4096},
            ) as resp:
                resp.raise_for_status()
                async for line in resp.aiter_lines():
                    if not line.startswith("data: "):
                        continue
                    payload = line[6:]
                    if payload.strip() == "[DONE]":
                        break
                    try:
                        data = json.loads(payload)
                        token = data["choices"][0]["delta"].get("content", "")
                        if token:
                            yield token.encode()
                    except (json.JSONDecodeError, KeyError, IndexError):
                        continue
    except httpx.ConnectError:
        yield b"[Erro: servidor LLM nao esta rodando]"
    except httpx.HTTPStatusError as exc:
        yield f"[Erro HTTP {exc.response.status_code}: verifique se o modelo esta carregado]".encode()
    except Exception as exc:
        log.warning("stream_summary failed: %s", exc)
        yield f"[Erro: {exc}]".encode()


async def get_autotags(
    title: str | None,
    body_text: str | None,
) -> list[str]:
    content = _build_content(title, body_text, max_chars=2000)
    if not content:
        return []
    messages = [{"role": "user", "content": _AUTOTAG_PROMPT.format(content=content)}]
    try:
        async with httpx.AsyncClient(timeout=120.0) as client:
            resp = await client.post(
                f"{settings.llm_url}/v1/chat/completions",
                json={"model": settings.llm_model, "messages": messages, "stream": False, "max_tokens": 1024},
            )
            resp.raise_for_status()
            raw = resp.json()["choices"][0]["message"]["content"]
            tags = [t.strip().lower() for t in raw.split(",") if t.strip()]
            return [t for t in tags if t][:8]
    except httpx.ConnectError:
        raise RuntimeError("Servidor LLM não está rodando")
    except Exception as exc:
        log.warning("get_autotags failed: %s", exc)
        raise
