# Copyright (c) 2026 Beijing Volcano Engine Technology Co., Ltd.
# SPDX-License-Identifier: AGPL-3.0
"""Passthrough parser for JSON/JSONL files — stores the file as-is without splitting."""

from pathlib import Path
from typing import List, Optional, Union

from openviking.parse.base import NodeType, ParseResult, ResourceNode
from openviking.parse.parsers.base_parser import BaseParser
from openviking.storage.viking_fs import get_viking_fs
from openviking_cli.utils.uri import VikingURI


class JSONParser(BaseParser):
    """Store JSON/JSONL files as a single resource without content splitting."""

    @property
    def supported_extensions(self) -> List[str]:
        return [".json", ".jsonl", ".ndjson"]

    async def parse(self, source: Union[str, Path], instruction: str = "", **kwargs) -> ParseResult:
        file_path = Path(source) if isinstance(source, str) else source
        if not file_path.exists():
            raise FileNotFoundError(f"JSON file not found: {source}")

        viking_fs = get_viking_fs()
        temp_uri = viking_fs.create_temp_uri()

        content = file_path.read_bytes()
        original_filename = file_path.name.replace(" ", "_")
        stem = file_path.stem.replace(" ", "_")
        root_dir_name = VikingURI.sanitize_segment(stem)
        root_dir_uri = f"{temp_uri}/{root_dir_name}"
        await viking_fs.mkdir(root_dir_uri, exist_ok=True)
        await viking_fs.write_file_bytes(f"{root_dir_uri}/{original_filename}", content)

        root_node = ResourceNode(
            type=NodeType.ROOT,
            title=stem,
            level=0,
            children=[],
            meta={
                "content_type": "data",
                "format": file_path.suffix.lstrip("."),
                "original_filename": original_filename,
                "size_bytes": len(content),
            },
        )

        return ParseResult(
            root=root_node,
            source_path=str(file_path),
            temp_dir_path=temp_uri,
            source_format=file_path.suffix.lstrip("."),
            parser_name="JSONParser",
            meta={"content_type": "data", "format": file_path.suffix.lstrip(".")},
        )

    async def parse_content(
        self, content: str, source_path: Optional[str] = None, instruction: str = "", **kwargs
    ) -> ParseResult:
        viking_fs = get_viking_fs()
        temp_uri = viking_fs.create_temp_uri()

        filename = Path(source_path).name if source_path else "content.json"
        stem = Path(filename).stem
        root_dir_name = VikingURI.sanitize_segment(stem)
        root_dir_uri = f"{temp_uri}/{root_dir_name}"
        await viking_fs.mkdir(root_dir_uri, exist_ok=True)
        await viking_fs.write_file(f"{root_dir_uri}/{filename}", content)

        root_node = ResourceNode(
            type=NodeType.ROOT,
            title=stem,
            level=0,
            children=[],
            meta={
                "content_type": "data",
                "format": Path(filename).suffix.lstrip("."),
                "original_filename": filename,
                "size_bytes": len(content.encode("utf-8")),
            },
        )

        return ParseResult(
            root=root_node,
            source_path=source_path,
            temp_dir_path=temp_uri,
            source_format=Path(filename).suffix.lstrip("."),
            parser_name="JSONParser",
            meta={"content_type": "data"},
        )
