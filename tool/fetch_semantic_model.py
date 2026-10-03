# /// script
# requires-python = ">=3.12"
# dependencies = ["huggingface-hub==1.32.0"]
# ///
"""Fetch, verify, and atomically stage the pinned BGE runtime assets."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import tempfile
from pathlib import Path

REPOSITORY = "BAAI/bge-base-en-v1.5"
REVISION = "a5beb1e3e68b9ab74eb54cfd186867f64f240e1a"
REQUIRED_FILES = (
    "onnx/model.onnx",
    "config.json",
    "tokenizer.json",
    "tokenizer_config.json",
    "special_tokens_map.json",
    "vocab.txt",
    "README.md",
)


def fetch_model(
    manifest_path: Path,
    private_directory: Path,
    runtime_directory: Path,
    *,
    downloader=None,
) -> None:
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    if manifest.get("repository") != REPOSITORY or manifest.get("revision") != REVISION:
        raise ValueError("manifest repository or revision is not approved")
    if tuple(manifest.get("files", {}).keys()) != tuple(sorted(REQUIRED_FILES)):
        raise ValueError("manifest file allow-list is not exact")
    if downloader is None:
        from huggingface_hub import snapshot_download

        downloader = snapshot_download

    private_directory.mkdir(parents=True, exist_ok=True)
    downloader(
        repo_id=REPOSITORY,
        revision=REVISION,
        allow_patterns=list(REQUIRED_FILES),
        local_dir=str(private_directory),
    )
    for relative_name in REQUIRED_FILES:
        expected = manifest["files"][relative_name]
        source = private_directory / relative_name
        if not source.is_file() or source.stat().st_size != expected["size"]:
            raise ValueError(f"model asset size mismatch: {relative_name}")
        digest = _sha256(source)
        if digest != expected["sha256"]:
            raise ValueError(f"model asset checksum mismatch: {relative_name}")

    runtime_directory.mkdir(parents=True, exist_ok=True)
    for relative_name in REQUIRED_FILES:
        source = private_directory / relative_name
        destination_name = "model.onnx" if relative_name == "onnx/model.onnx" else relative_name
        _atomic_copy(source, runtime_directory / destination_name)


def _sha256(source: Path) -> str:
    digest = hashlib.sha256()
    with source.open("rb") as input_file:
        while chunk := input_file.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def _atomic_copy(source: Path, destination: Path) -> None:
    descriptor, temporary_name = tempfile.mkstemp(prefix=f".{destination.name}.", dir=destination.parent)
    try:
        with os.fdopen(descriptor, "wb") as target, source.open("rb") as origin:
            shutil.copyfileobj(origin, target)
            target.flush()
            os.fsync(target.fileno())
        os.replace(temporary_name, destination)
    except BaseException:
        try:
            os.unlink(temporary_name)
        except FileNotFoundError:
            pass
        raise


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", type=Path, default=Path(__file__).with_name("semantic_model_manifest.json"))
    parser.add_argument("--private-dir", type=Path, default=Path("private/models/bge-base-en-v1.5"))
    parser.add_argument("--runtime-dir", type=Path, default=Path("assets/semantic"))
    arguments = parser.parse_args()
    fetch_model(arguments.manifest, arguments.private_dir, arguments.runtime_dir)
    print(f"verified and staged {len(REQUIRED_FILES)} semantic model assets")


if __name__ == "__main__":
    main()
