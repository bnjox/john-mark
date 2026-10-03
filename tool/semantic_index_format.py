"""Deterministic writer for the version 1 semantic scripture index."""

from __future__ import annotations

import hashlib
import json
import math
import os
import sqlite3
import struct
import tempfile
from collections.abc import Iterable, Sequence
from dataclasses import dataclass
from pathlib import Path

MAGIC = b"SCRIPIDX"
FORMAT_VERSION = 1
DIMENSIONS = 768
CREATED_BY_VERSION = "semantic-index-tool/1"


@dataclass(frozen=True)
class Verse:
    translation_id: str
    book: int
    chapter: int
    verse: int
    text: str


def read_verses(database: Path) -> list[Verse]:
    """Read single verses in canonical deterministic order."""
    connection = sqlite3.connect(database)
    try:
        version = connection.execute("PRAGMA user_version").fetchone()[0]
        if version != 1:
            raise ValueError(f"unsupported Bible schema version: {version}")
        rows = connection.execute(
            """
            SELECT translation_id, book_number, chapter, start_verse, display_text
            FROM passages
            WHERE start_verse = end_verse
            ORDER BY translation_id, book_number, chapter, start_verse
            """
        ).fetchall()
    finally:
        connection.close()
    return [Verse(str(row[0]), int(row[1]), int(row[2]), int(row[3]), str(row[4])) for row in rows]


def bible_fingerprint(verses: Iterable[Verse], schema_version: int = 1) -> str:
    """Hash schema and sorted verse fields using u32-LE length-prefixed UTF-8."""
    digest = hashlib.sha256()
    _hash_field(digest, str(schema_version))
    for item in sorted(verses, key=lambda v: (v.translation_id, v.book, v.chapter, v.verse)):
        for value in (
            item.translation_id,
            str(item.book),
            str(item.chapter),
            str(item.verse),
            str(item.verse),
            item.text,
        ):
            _hash_field(digest, value)
    return digest.hexdigest()


def _hash_field(digest: "hashlib._Hash", value: str) -> None:
    encoded = value.encode("utf-8")
    digest.update(struct.pack("<I", len(encoded)))
    digest.update(encoded)


def quantize(vector: Sequence[float]) -> tuple[float, bytes]:
    """Normalize and symmetrically quantize one vector to signed int8."""
    if len(vector) != DIMENSIONS:
        raise ValueError(f"expected {DIMENSIONS} dimensions, got {len(vector)}")
    norm = math.sqrt(math.fsum(float(value) ** 2 for value in vector))
    if not math.isfinite(norm) or norm == 0:
        raise ValueError("embedding must have a finite non-zero norm")
    normalized = [float(value) / norm for value in vector]
    maximum = max(abs(value) for value in normalized)
    scale = maximum / 127.0
    values = [max(-127, min(127, round(value / scale))) for value in normalized]
    return scale, struct.pack(f"<{DIMENSIONS}b", *values)


def write_index(
    output: Path,
    verses: Sequence[Verse],
    embeddings: Sequence[Sequence[float]],
    *,
    model_id: str,
    model_revision: str,
    fingerprint: str,
) -> None:
    if len(verses) != len(embeddings):
        raise ValueError("verse and embedding counts differ")
    translations = sorted({verse.translation_id for verse in verses})
    if len(translations) > 256:
        raise ValueError("index supports at most 256 translations")
    ordinals = {translation: index for index, translation in enumerate(translations)}
    metadata = json.dumps(
        {
            "modelId": model_id,
            "modelRevision": model_revision,
            "bibleFingerprint": fingerprint,
            "translations": translations,
            "quantization": "symmetric-int8-per-row",
            "createdByVersion": CREATED_BY_VERSION,
        },
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")

    output.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(prefix=f".{output.name}.", dir=output.parent)
    try:
        with os.fdopen(descriptor, "wb") as target:
            target.write(MAGIC)
            target.write(struct.pack("<HHII", FORMAT_VERSION, DIMENSIONS, len(metadata), len(verses)))
            target.write(metadata)
            for verse, embedding in zip(verses, embeddings, strict=True):
                if not (0 < verse.book <= 255 and 0 < verse.chapter <= 65535 and 0 < verse.verse <= 65535):
                    raise ValueError("verse reference is outside index bounds")
                scale, values = quantize(embedding)
                target.write(struct.pack("<BBHHf", ordinals[verse.translation_id], verse.book, verse.chapter, verse.verse, scale))
                target.write(values)
            target.flush()
            os.fsync(target.fileno())
        os.replace(temporary_name, output)
    except BaseException:
        try:
            os.unlink(temporary_name)
        except FileNotFoundError:
            pass
        raise
