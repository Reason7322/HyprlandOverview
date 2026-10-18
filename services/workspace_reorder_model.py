"""Pure data model and guarded file helpers for workspace reordering."""

from __future__ import annotations

import datetime
import fcntl
import hashlib
import json
import os
import pathlib
import re
import tempfile
from collections.abc import Iterable, Mapping
from typing import Any


SCHEMA_VERSION = 2
LEGACY_SCHEMA_VERSION = 1
MIN_WORKSPACE_ID = 1
MAX_WORKSPACE_ID = 2_147_483_647
DEFAULT_WORKSPACES = tuple(range(1, 11))


class RuleRewrite:
    def __init__(self, payload: bytes, rows: list[dict[str, Any]]) -> None:
        self.bytes = payload
        self.rows = rows


def valid_workspace_id(value: object) -> bool:
    return (
        isinstance(value, int)
        and not isinstance(value, bool)
        and MIN_WORKSPACE_ID <= value <= MAX_WORKSPACE_ID
    )


def canonical_slots(ids: Iterable[int]) -> list[int]:
    values = set(DEFAULT_WORKSPACES)
    for workspace_id in ids:
        if not valid_workspace_id(workspace_id):
            raise ValueError(f"invalid workspace id: {workspace_id!r}")
        values.add(workspace_id)
    return sorted(values)


def _validated_unique_ids(values: list[int], label: str) -> list[int]:
    if not isinstance(values, list):
        raise ValueError(f"{label} must be an array")
    for workspace_id in values:
        if not valid_workspace_id(workspace_id):
            raise ValueError(f"invalid workspace id in {label}: {workspace_id!r}")
    if len(set(values)) != len(values):
        raise ValueError(f"duplicate workspace id in {label}")
    return values


def build_permutation(
    slot_order: list[int], identity_order: list[int]
) -> dict[int, int]:
    slots = _validated_unique_ids(slot_order, "slot order")
    identities = _validated_unique_ids(identity_order, "identity order")
    if len(slots) != len(identities) or set(slots) != set(identities):
        raise ValueError("slot and identity orders must contain the same IDs")
    return {
        identity: slot
        for slot, identity in zip(slots, identities, strict=True)
        if identity != slot
    }


def allocate_temporary_ids(count: int, forbidden: set[int]) -> list[int]:
    if not isinstance(count, int) or isinstance(count, bool) or count < 0:
        raise ValueError("temporary workspace count must be a non-negative integer")
    blocked = set()
    for workspace_id in forbidden:
        if not valid_workspace_id(workspace_id):
            raise ValueError(f"invalid forbidden workspace id: {workspace_id!r}")
        blocked.add(workspace_id)
    result = []
    candidate = MAX_WORKSPACE_ID
    while len(result) < count and candidate >= MIN_WORKSPACE_ID:
        if candidate not in blocked:
            result.append(candidate)
        candidate -= 1
    if len(result) != count:
        raise ValueError("not enough collision-free temporary workspace IDs")
    return result


def _skip_lua_quoted(source: bytes, index: int, end: int) -> int:
    quote = source[index]
    index += 1
    while index < end:
        if source[index] == 92:  # backslash
            index += 2
        elif source[index] == quote:
            return index + 1
        else:
            index += 1
    raise ValueError("unterminated Lua string")


def _long_bracket_end(source: bytes, index: int, end: int) -> int | None:
    match = re.match(rb"\[(=*)\[", source[index:end])
    if match is None:
        return None
    closing = b"]" + match.group(1) + b"]"
    found = source.find(closing, index + len(match.group(0)), end)
    if found < 0:
        raise ValueError("unterminated Lua long string or comment")
    return found + len(closing)


def _brace_events(source: bytes, start: int, end: int):
    index = start
    while index < end:
        if source.startswith(b"--", index):
            long_end = _long_bracket_end(source, index + 2, end)
            if long_end is not None:
                index = long_end
            else:
                newline = source.find(b"\n", index + 2, end)
                index = end if newline < 0 else newline + 1
            continue
        if source[index] in (34, 39):
            index = _skip_lua_quoted(source, index, end)
            continue
        long_end = _long_bracket_end(source, index, end)
        if long_end is not None:
            index = long_end
            continue
        if source[index] in (123, 125):
            yield index, source[index]
        index += 1


def _table_and_rows(source: bytes) -> tuple[tuple[int, int], list[tuple[int, int]]]:
    declaration = re.compile(
        rb"(?m)^[ \t]*local[ \t]+workspace_windows[ \t]*=[ \t]*\{"
    )
    declarations = list(declaration.finditer(source))
    if len(declarations) != 1:
        raise ValueError("expected exactly one local workspace_windows table")
    outer_open = declarations[0].end() - 1
    depth = 0
    outer_close = None
    row_start = None
    rows = []
    for position, token in _brace_events(source, outer_open, len(source)):
        if token == 123:
            if depth == 1:
                row_start = position
            depth += 1
        else:
            depth -= 1
            if depth < 0:
                raise ValueError("unbalanced Lua table braces")
            if depth == 1 and row_start is not None:
                rows.append((row_start, position + 1))
                row_start = None
            if depth == 0:
                outer_close = position
                break
    if outer_close is None or depth != 0:
        raise ValueError("unterminated workspace_windows table")
    return (outer_open, outer_close + 1), rows


def _row_class(row: bytes) -> str:
    match = re.search(
        rb"\bclass\s*=\s*(?:\"((?:\\.|[^\"\\])*)\"|"
        rb"'((?:\\.|[^'\\])*)'|\[\[(.*?)\]\])",
        row,
        re.DOTALL,
    )
    if match is None:
        raise ValueError("workspace_windows row has no literal class")
    value = next(group for group in match.groups() if group is not None)
    return value.decode("utf-8")


def rewrite_workspace_windows(
    source: bytes, mapping: Mapping[int, int]
) -> RuleRewrite:
    if not isinstance(source, bytes):
        raise ValueError("rules source must be bytes")
    normalized_mapping = {}
    for source_id, destination_id in mapping.items():
        if not valid_workspace_id(source_id) or not valid_workspace_id(destination_id):
            raise ValueError("rule mapping contains an invalid workspace ID")
        normalized_mapping[source_id] = destination_id
    if len(set(normalized_mapping.values())) != len(normalized_mapping):
        raise ValueError("rule mapping destinations must be unique")

    table_span, row_spans = _table_and_rows(source)
    outside = source[:table_span[0]] + source[table_span[1]:]
    for match in re.finditer(
        rb"\bworkspace\s*=\s*([\"'])([0-9]+)\1", outside
    ):
        if int(match.group(2)) in normalized_mapping:
            raise ValueError("affected workspace assignment exists outside workspace_windows")

    workspace_pattern = re.compile(
        rb"\bworkspace\s*=\s*([\"'])([0-9]+)\1"
    )
    replacements = []
    changed_rows = []
    for row_start, row_end in row_spans:
        row = source[row_start:row_end]
        matches = list(workspace_pattern.finditer(row))
        if len(matches) != 1:
            raise ValueError("workspace_windows row must have one literal workspace")
        source_id = int(matches[0].group(2))
        if source_id not in normalized_mapping:
            continue
        destination_id = normalized_mapping[source_id]
        if source_id == destination_id:
            continue
        digit_start = row_start + matches[0].start(2)
        digit_end = row_start + matches[0].end(2)
        replacements.append((digit_start, digit_end, str(destination_id).encode("ascii")))
        changed_rows.append({
            "class": _row_class(row),
            "source": source_id,
            "destination": destination_id,
        })

    rewritten = source
    for start, end, replacement in reversed(replacements):
        rewritten = rewritten[:start] + replacement + rewritten[end:]
    return RuleRewrite(rewritten, changed_rows)


def _sha256(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def _validate_metadata(raw: object) -> dict[str, Any]:
    if not isinstance(raw, dict):
        raise ValueError("metadata root must be an object")
    version = raw.get("version")
    if version not in (LEGACY_SCHEMA_VERSION, SCHEMA_VERSION):
        raise ValueError(f"unsupported metadata version: {version!r}")
    names = raw.get("names", {})
    order = raw.get("order", [])
    if not isinstance(names, dict):
        raise ValueError("metadata names must be an object")
    if not isinstance(order, list):
        raise ValueError("metadata order must be an array")
    for key, value in names.items():
        try:
            workspace_id = int(key)
        except (TypeError, ValueError) as error:
            raise ValueError(f"invalid workspace name key: {key!r}") from error
        if str(workspace_id) != str(key) or not valid_workspace_id(workspace_id):
            raise ValueError(f"invalid workspace name key: {key!r}")
        if not isinstance(value, str):
            raise ValueError(f"workspace name {key!r} must be a string")
    for workspace_id in order:
        if not valid_workspace_id(workspace_id):
            raise ValueError(f"invalid workspace id in order: {workspace_id!r}")
    return raw


def _fsync_directory(path: pathlib.Path) -> None:
    descriptor = os.open(path, os.O_RDONLY | getattr(os, "O_DIRECTORY", 0))
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def _atomic_write(path: pathlib.Path, payload: bytes) -> None:
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{path.name}.write-", dir=path.parent
    )
    temporary = pathlib.Path(temporary_name)
    try:
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(payload)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
        _fsync_directory(path.parent)
    except Exception:
        temporary.unlink(missing_ok=True)
        raise


def _timestamp() -> str:
    return datetime.datetime.now(datetime.UTC).strftime("%Y%m%dT%H%M%S%fZ")


def _create_verified_backup(path: pathlib.Path, payload: bytes) -> pathlib.Path:
    backup = path.with_name(f"{path.name}.schema1-backup-{_timestamp()}")
    with backup.open("xb") as stream:
        stream.write(payload)
        stream.flush()
        os.fsync(stream.fileno())
    _fsync_directory(path.parent)
    if backup.read_bytes() != payload:
        raise OSError(f"metadata backup verification failed: {backup}")
    return backup


def migrate_metadata(path: pathlib.Path) -> dict[str, Any]:
    """Migrate schema 1 to canonical schema 2 under an advisory file lock."""

    path = pathlib.Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    lock_path = path.with_name(f"{path.name}.lock")
    with lock_path.open("a+b") as lock_stream:
        fcntl.flock(lock_stream.fileno(), fcntl.LOCK_EX)
        if not path.exists():
            payload = json.dumps(
                {"version": SCHEMA_VERSION, "names": {},
                 "order": list(DEFAULT_WORKSPACES)},
                ensure_ascii=False,
                indent=2,
            ).encode("utf-8") + b"\n"
            _atomic_write(path, payload)
            return {
                "version": 1,
                "status": "created",
                "backupPath": None,
                "beforeSha256": None,
                "afterSha256": _sha256(payload),
            }

        original = path.read_bytes()
        try:
            raw = _validate_metadata(json.loads(original.decode("utf-8")))
        except (UnicodeDecodeError, json.JSONDecodeError) as error:
            raise ValueError(f"invalid metadata JSON: {error}") from error

        if raw["version"] == SCHEMA_VERSION:
            return {
                "version": 1,
                "status": "already_current",
                "backupPath": None,
                "beforeSha256": _sha256(original),
                "afterSha256": _sha256(original),
            }

        backup = _create_verified_backup(path, original)
        migrated = dict(raw)
        migrated["version"] = SCHEMA_VERSION
        ids = list(raw["order"]) + [int(key) for key in raw["names"]]
        migrated["order"] = canonical_slots(ids)
        payload = json.dumps(migrated, ensure_ascii=False, indent=2).encode("utf-8") + b"\n"
        try:
            _atomic_write(path, payload)
            verified = _validate_metadata(json.loads(path.read_text(encoding="utf-8")))
            if verified["version"] != SCHEMA_VERSION:
                raise OSError("metadata migration verification returned wrong schema")
        except Exception:
            _atomic_write(path, original)
            raise
        return {
            "version": 1,
            "status": "migrated",
            "backupPath": str(backup),
            "beforeSha256": _sha256(original),
            "afterSha256": _sha256(payload),
        }
