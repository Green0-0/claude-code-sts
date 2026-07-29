#!/usr/bin/env python3
"""Read Pokemon Showdown's TypeScript data tables as plain Python dicts.

Showdown ships its dex as TypeScript source rather than JSON, and the tables are
peppered with event handlers — `onHit(target, source, move) { ... }` — that no
JSON parser will touch. So this is a small recursive-descent reader for the
subset of the object-literal syntax those files actually use: objects, arrays,
strings, numbers, the three keywords, and comments. Anything it does not
recognise (a method body, a call, an arrow function) is skipped over rather than
guessed at, which is exactly right here — the mechanics we need are all data,
and the behaviour we cannot represent is the part written as code.

Used by build_data.py; not a command-line tool of its own.
"""

from __future__ import annotations

import os
import re

_WS = " \t\r\n"
_NUMBER = re.compile(r"-?(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?")
_ESCAPES = {"n": "\n", "t": "\t", "r": "\r", "b": "\b", "f": "\f", "0": "\0"}


class _Skipped:
    """Marks a value we chose not to interpret, so callers can drop the key."""

    def __repr__(self) -> str:
        return "<skipped>"


SKIPPED = _Skipped()


def _skip_trivia(s: str, i: int) -> int:
    """Advance past whitespace and both comment styles."""
    while i < len(s):
        c = s[i]
        if c in _WS:
            i += 1
        elif s.startswith("//", i):
            nl = s.find("\n", i)
            i = len(s) if nl < 0 else nl + 1
        elif s.startswith("/*", i):
            end = s.find("*/", i)
            i = len(s) if end < 0 else end + 2
        else:
            break
    return i


def _read_string(s: str, i: int) -> tuple[str, int]:
    quote = s[i]
    i += 1
    out: list[str] = []
    while i < len(s):
        c = s[i]
        if c == "\\":
            nxt = s[i + 1]
            if nxt == "u":
                out.append(chr(int(s[i + 2:i + 6], 16)))
                i += 6
                continue
            out.append(_ESCAPES.get(nxt, nxt))
            i += 2
            continue
        if c == quote:
            return "".join(out), i + 1
        out.append(c)
        i += 1
    raise ValueError("unterminated string")


def _skip_expression(s: str, i: int) -> int:
    """Skip a value we do not parse, stopping at the comma or brace after it."""
    depth = 0
    while i < len(s):
        c = s[i]
        if c in "\"'`":
            _, i = _read_string(s, i)
            continue
        if s.startswith("//", i) or s.startswith("/*", i):
            i = _skip_trivia(s, i)
            continue
        if c in "([{":
            depth += 1
        elif c in ")]}":
            if depth == 0:
                return i
            depth -= 1
        elif c == "," and depth == 0:
            return i
        i += 1
    return i


def _skip_block(s: str, i: int, open_c: str, close_c: str) -> int:
    """Skip a balanced (...) or {...} run, starting on its opening character."""
    while i < len(s) and s[i] != open_c:
        i += 1
    depth = 0
    while i < len(s):
        c = s[i]
        if c in "\"'`":
            _, i = _read_string(s, i)
            continue
        # Comments before quotes would be wrong (a URL contains "//"); after
        # them is right, and it stops an apostrophe in "don't" mid-comment from
        # being read as the start of a string and swallowing the real braces.
        if s.startswith("//", i) or s.startswith("/*", i):
            i = _skip_trivia(s, i)
            continue
        if c == open_c:
            depth += 1
        elif c == close_c:
            depth -= 1
            if depth == 0:
                return i + 1
        i += 1
    return i


def _read_array(s: str, i: int) -> tuple[list, int]:
    i += 1
    out: list = []
    while True:
        i = _skip_trivia(s, i)
        if i >= len(s):
            raise ValueError("unterminated array")
        if s[i] == "]":
            return out, i + 1
        if s[i] == ",":
            i += 1
            continue
        value, i = _read_value(s, i)
        if value is not SKIPPED:
            out.append(value)


def _read_object(s: str, i: int) -> tuple[dict, int]:
    i += 1
    out: dict = {}
    while True:
        i = _skip_trivia(s, i)
        if i >= len(s):
            raise ValueError("unterminated object")
        if s[i] == "}":
            return out, i + 1
        if s[i] == ",":
            i += 1
            continue
        if s[i] in "\"'`":
            key, i = _read_string(s, i)
        elif s[i] in "[.":
            # A computed key or a spread; neither appears in the data we want.
            i = _skip_expression(s, i)
            continue
        else:
            j = i
            while j < len(s) and (s[j].isalnum() or s[j] in "_$"):
                j += 1
            key, i = s[i:j], j
        i = _skip_trivia(s, i)
        if i < len(s) and s[i] == ":":
            value, i = _read_value(s, _skip_trivia(s, i + 1))
            if value is not SKIPPED:
                out[key] = value
        elif i < len(s) and s[i] == "(":
            # Method shorthand, e.g. `onHit(pokemon) { ... }`. The body is
            # behaviour, not data, so drop the whole property.
            i = _skip_block(s, i, "(", ")")
            i = _skip_block(s, i, "{", "}")
        else:
            raise ValueError(f"unexpected token after key {key!r}")


def _read_value(s: str, i: int):
    c = s[i]
    if c == "{":
        return _read_object(s, i)
    if c == "[":
        return _read_array(s, i)
    if c in "\"'`":
        return _read_string(s, i)
    for word, value in (("true", True), ("false", False),
                        ("null", None), ("undefined", None)):
        if s.startswith(word, i) and not (s[i + len(word)].isalnum()
                                          or s[i + len(word)] in "_$"):
            return value, i + len(word)
    m = _NUMBER.match(s, i)
    if m:
        text = m.group(0)
        return (float(text) if "." in text or "e" in text.lower()
                else int(text)), m.end()
    return SKIPPED, _skip_expression(s, i)


def parse_table(text: str) -> dict:
    """Parse the single exported object literal in a Showdown data file."""
    m = re.search(r"=\s*\{", text)
    if not m:
        raise ValueError("no exported table found")
    table, _ = _read_object(text, m.end() - 1)
    return table


def load_table(cache: str, name: str) -> dict:
    path = os.path.join(cache, "showdown", name)
    if not os.path.exists(path):
        return {}
    with open(path, "r", encoding="utf-8") as fh:
        return parse_table(fh.read())
