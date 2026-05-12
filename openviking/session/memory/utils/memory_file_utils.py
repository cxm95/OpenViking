from typing import Any, Dict, List, Optional

from openviking.session.memory.utils import parse_memory_file_with_fields, serialize_with_metadata
from openviking.session.memory.utils.link_renderer import LinkRenderer


class MemoryFileUtils:
    """High-level read/write utilities for memory files.

    Encapsulates parse + strip_links (read) and serialize + render_links (write),
    so callers don't need to worry about the correct ordering.
    """

    @staticmethod
    def read_file_content(raw_content: str) -> Dict[str, Any]:
        """Parse a memory file and strip rendered links from content.

        Returns a dict with all MEMORY_FIELDS plus "content" (plain text, no links).
        """
        parsed = parse_memory_file_with_fields(raw_content)
        parsed["content"] = LinkRenderer.strip_links(parsed.get("content", ""))
        return parsed

    @staticmethod
    def write_file_content(
        metadata: Dict[str, Any],
        source_uri: str,
        content_template: Optional[str] = None,
        extract_context: Any = None,
    ) -> str:
        """Serialize metadata and render links in the content body.

        Handles serialize_with_metadata (including content_template) first,
        then renders links in the body part (before MEMORY_FIELDS comment)
        so content_template output is not overwritten.
        """
        links = metadata.get("links", [])
        full_content = serialize_with_metadata(
            metadata.copy(),
            content_template=content_template,
            extract_context=extract_context,
        )
        if not links:
            return full_content
        # Only render links in the body, not in the MEMORY_FIELDS comment
        split = LinkRenderer._MEMORY_FIELDS_RE.split(full_content, maxsplit=1)
        if len(split) == 3:
            body, separator, remainder = split
            rendered_body = LinkRenderer.render_links(body, source_uri, links)
            return rendered_body + separator + remainder
        return full_content
