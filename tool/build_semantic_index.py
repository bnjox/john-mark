# /// script
# requires-python = ">=3.12"
# dependencies = [
#   "numpy==2.5.3",
#   "sentence-transformers==6.0.1",
# ]
# ///
"""Build the private semantic scripture index without printing verse text."""

from __future__ import annotations

import argparse
import time
from pathlib import Path

from semantic_index_format import bible_fingerprint, read_verses, write_index

MODEL_ID = "BAAI/bge-base-en-v1.5"
MODEL_REVISION = "a5beb1e3e68b9ab74eb54cfd186867f64f240e1a"


def build_index(database: Path, model: Path, output: Path, embedder=None) -> int:
    verses = read_verses(database)
    if not verses:
        raise ValueError("Bible database contains no single verses")
    if embedder is None:
        from sentence_transformers import SentenceTransformer

        embedder = SentenceTransformer(
            str(model),
            backend="onnx",
            model_kwargs={"file_name": "onnx/model.onnx"},
            local_files_only=True,
        )
    embeddings = embedder.encode(
        [verse.text for verse in verses],
        batch_size=32,
        show_progress_bar=False,
        convert_to_numpy=True,
        normalize_embeddings=True,
    )
    write_index(
        output,
        verses,
        embeddings,
        model_id=MODEL_ID,
        model_revision=MODEL_REVISION,
        fingerprint=bible_fingerprint(verses),
    )
    return len(verses)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--database", type=Path, required=True)
    parser.add_argument("--model", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    arguments = parser.parse_args()
    started = time.monotonic()
    count = build_index(arguments.database, arguments.model, arguments.output)
    elapsed = time.monotonic() - started
    print(f"indexed {count} verses in {elapsed:.1f}s ({arguments.output.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
