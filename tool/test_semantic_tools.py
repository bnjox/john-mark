# /// script
# requires-python = ">=3.12"
# dependencies = []
# ///
"""Pure unittest coverage for deterministic semantic asset tooling."""

from __future__ import annotations

import hashlib
import json
import sqlite3
import struct
import tempfile
import unittest
from pathlib import Path
from unittest.mock import Mock

from build_semantic_index import MODEL_ID, MODEL_REVISION, build_index
from fetch_semantic_model import REQUIRED_FILES, REPOSITORY, REVISION, fetch_model
from semantic_index_format import DIMENSIONS, MAGIC, bible_fingerprint, read_verses


class FakeEmbedder:
    def __init__(self) -> None:
        self.texts: list[str] = []

    def encode(self, texts, **options):
        self.texts = list(texts)
        self.options = options
        vectors = []
        for index, _ in enumerate(texts):
            vector = [0.0] * DIMENSIONS
            vector[index] = 3.0
            vector[index + 2] = 4.0
            vectors.append(vector)
        return vectors


class IndexToolTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.database = self.root / "bibles.db"
        connection = sqlite3.connect(self.database)
        connection.executescript(
            """
            PRAGMA user_version = 1;
            CREATE TABLE passages (
              translation_id TEXT, book_number INTEGER, chapter INTEGER,
              start_verse INTEGER, end_verse INTEGER, display_text TEXT
            );
            """
        )
        connection.executemany(
            "INSERT INTO passages VALUES (?, ?, ?, ?, ?, ?)",
            [
                ("zeta", 43, 3, 16, 17, "excluded range"),
                ("zeta", 43, 3, 16, 16, "second"),
                ("alpha", 1, 1, 1, 1, "first"),
            ],
        )
        connection.commit()
        connection.close()

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def test_reads_only_single_verses_in_deterministic_order(self) -> None:
        verses = read_verses(self.database)
        self.assertEqual([verse.text for verse in verses], ["first", "second"])
        self.assertEqual(bible_fingerprint(verses), bible_fingerprint(reversed(verses)))

    def test_builds_normalized_int8_rows_and_metadata_atomically(self) -> None:
        output = self.root / "index.bin"
        output.write_bytes(b"old")
        embedder = FakeEmbedder()
        self.assertEqual(build_index(self.database, self.root, output, embedder), 2)
        payload = output.read_bytes()
        self.assertEqual(payload[:8], MAGIC)
        version, dimensions, metadata_length, rows = struct.unpack_from("<HHII", payload, 8)
        self.assertEqual((version, dimensions, rows), (1, DIMENSIONS, 2))
        metadata = json.loads(payload[20 : 20 + metadata_length])
        self.assertEqual(metadata["modelId"], MODEL_ID)
        self.assertEqual(metadata["modelRevision"], MODEL_REVISION)
        self.assertEqual(metadata["translations"], ["alpha", "zeta"])
        row_offset = 20 + metadata_length
        scale = struct.unpack_from("<f", payload, row_offset + 6)[0]
        values = struct.unpack_from(f"<{DIMENSIONS}b", payload, row_offset + 10)
        self.assertAlmostEqual(scale, 0.8 / 127, places=7)
        self.assertEqual(values[:3], (95, 0, 127))
        self.assertEqual(embedder.texts, ["first", "second"])

    def test_rejects_wrong_schema_without_replacing_output(self) -> None:
        connection = sqlite3.connect(self.database)
        connection.execute("PRAGMA user_version = 2")
        connection.close()
        output = self.root / "index.bin"
        output.write_bytes(b"keep")
        with self.assertRaisesRegex(ValueError, "schema version"):
            build_index(self.database, self.root, output, FakeEmbedder())
        self.assertEqual(output.read_bytes(), b"keep")


class FetchToolTests(unittest.TestCase):
    def test_uses_exact_pinned_download_and_verifies_before_runtime_copy(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            private = root / "private"
            runtime = root / "runtime"
            files = {}
            for name in sorted(REQUIRED_FILES):
                content = f"content:{name}".encode()
                files[name] = {"size": len(content), "sha256": hashlib.sha256(content).hexdigest()}
            manifest = root / "manifest.json"
            manifest.write_text(json.dumps({"repository": REPOSITORY, "revision": REVISION, "files": files}))

            def download(**arguments):
                self.assertEqual(arguments, {
                    "repo_id": REPOSITORY,
                    "revision": REVISION,
                    "allow_patterns": list(REQUIRED_FILES),
                    "local_dir": str(private),
                })
                for name in REQUIRED_FILES:
                    path = private / name
                    path.parent.mkdir(parents=True, exist_ok=True)
                    path.write_bytes(f"content:{name}".encode())

            downloader = Mock(side_effect=download)
            fetch_model(manifest, private, runtime, downloader=downloader)
            downloader.assert_called_once()
            self.assertEqual((runtime / "model.onnx").read_bytes(), b"content:onnx/model.onnx")
            self.assertEqual((runtime / "README.md").read_bytes(), b"content:README.md")


if __name__ == "__main__":
    unittest.main()
