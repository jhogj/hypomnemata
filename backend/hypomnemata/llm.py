"""Cliente LLM via OpenAI-compatible /v1/chat/completions.

Compatível com MLX-LM (porta 8080), LM Studio (porta 1234) e Ollama (porta 11434).
Configure HYPO_LLM_URL e HYPO_LLM_MODEL para trocar de provider sem mexer no código.
"""
from __future__ import annotations

import json
import logging
import re
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


def summarize_sync(title: str | None, body_text: str | None) -> str | None:
    """Versão síncrona para uso dentro de workers asyncio.to_thread.

    Retorna o resumo ou None se o servidor LLM não estiver disponível.
    Nunca levanta exceção — falha silenciosa para não bloquear o scraping.
    """
    import httpx

    content = _build_content(title, body_text)
    if not content:
        return None
    messages = [{"role": "user", "content": _SUMMARY_PROMPT.format(content=content)}]
    try:
        with httpx.Client(timeout=120.0) as client:
            resp = client.post(
                f"{settings.llm_url}/v1/chat/completions",
                json={"model": settings.llm_model, "messages": messages, "stream": False, "max_tokens": 4096},
            )
            resp.raise_for_status()
            return resp.json()["choices"][0]["message"]["content"].strip() or None
    except Exception as exc:
        log.debug("auto-summarize ignorado (LLM indisponível): %s", exc)
        return None


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


_CHAT_SYSTEM_PROMPT = """\
Você é um assistente que responde perguntas sobre o conteúdo fornecido abaixo.
Responda sempre em português, de forma direta e concisa.
Baseie suas respostas apenas no conteúdo a seguir — não invente informações.

CONTEÚDO:
{context}"""


def get_autotags_sync(title: str | None, body_text: str | None) -> list[str]:
    """Versão síncrona de get_autotags para uso dentro de workers asyncio.to_thread.

    Retorna lista de tags ou [] se o servidor LLM não estiver disponível.
    Nunca levanta exceção — falha silenciosa.
    """
    import httpx

    content = _build_content(title, body_text, max_chars=2000)
    if not content:
        return []
    messages = [{"role": "user", "content": _AUTOTAG_PROMPT.format(content=content)}]
    try:
        with httpx.Client(timeout=60.0) as client:
            resp = client.post(
                f"{settings.llm_url}/v1/chat/completions",
                json={"model": settings.llm_model, "messages": messages, "stream": False, "max_tokens": 512},
            )
            resp.raise_for_status()
            raw = resp.json()["choices"][0]["message"]["content"]
            tags = [t.strip().lower() for t in re.split(r"[,\n]+", raw) if t.strip()]
            return [t for t in tags if t][:8]
    except Exception as exc:
        log.debug("auto-tags ignoradas (LLM indisponível): %s", exc)
        return []


async def stream_chat(
    title: str | None,
    body_text: str | None,
    messages: list[dict],
) -> AsyncGenerator[bytes, None]:
    context = _build_content(title, body_text, max_chars=12000)
    if not context:
        return
    system = _CHAT_SYSTEM_PROMPT.format(context=context)
    full_messages = [{"role": "system", "content": system}] + messages
    timeout = httpx.Timeout(connect=5.0, read=None, write=10.0, pool=5.0)
    try:
        async with httpx.AsyncClient(timeout=timeout) as client:
            async with client.stream(
                "POST",
                f"{settings.llm_url}/v1/chat/completions",
                json={"model": settings.llm_model, "messages": full_messages, "stream": True, "max_tokens": 2048},
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
        log.warning("stream_chat failed: %s", exc)
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
            tags = [t.strip().lower() for t in re.split(r"[,\n]+", raw) if t.strip()]
            return [t for t in tags if t][:8]
    except httpx.ConnectError:
        raise RuntimeError("Servidor LLM não está rodando")
    except Exception as exc:
        log.warning("get_autotags failed: %s", exc)
        raise
