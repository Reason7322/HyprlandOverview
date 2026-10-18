#!/usr/bin/env python3
"""Guarded workspace-reorder coordinator CLI."""

from __future__ import annotations

import argparse
import datetime
import fcntl
import hashlib
import json
import os
import pathlib
import re
import subprocess
import tempfile
from dataclasses import dataclass
from typing import Any

from workspace_reorder_model import (
    SCHEMA_VERSION,
    allocate_temporary_ids,
    build_permutation,
    canonical_slots,
    migrate_metadata,
    rewrite_workspace_windows,
    valid_workspace_id,
)


@dataclass(frozen=True)
class LiveSnapshot:
    clients: list[dict[str, Any]]
    workspaces: list[dict[str, Any]]
    monitors: list[dict[str, Any]]
    active_workspace: dict[str, Any]
    active_window: dict[str, Any]
    workspace_rules: list[dict[str, Any]]


@dataclass(frozen=True)
class ConfigSnapshot:
    entrypoint: pathlib.Path
    rules_path: pathlib.Path
    rules_bytes: bytes
    dependency_hashes: dict[str, str]
    dependency_sources: dict[str, bytes]


@dataclass(frozen=True)
class TransactionPlan:
    request: dict[str, Any]
    slot_order: list[int]
    identity_order: list[int]
    mapping: dict[int, int]
    clients_by_source: dict[int, list[dict[str, Any]]]
    temporary_by_source: dict[int, int]
    monitor_by_source: dict[int, str]
    focus_by_monitor: dict[str, int]
    focused_monitor: str
    focused_window: str
    rule_bytes: bytes
    rule_rows: list[dict[str, Any]]
    metadata_bytes: bytes
    metadata_path: pathlib.Path | None
    config: ConfigSnapshot
    snapshot: LiveSnapshot


@dataclass(frozen=True)
class TransactionResult:
    status: str
    message: str
    journal_path: pathlib.Path | None
    changed: bool


class HyprctlAdapter:
    """Small synchronous adapter; inspection calls never dispatch."""

    def _run(self, command: list[str]) -> str:
        result = subprocess.run(
            command,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            check=False,
        )
        if result.returncode != 0:
            raise OSError(f"command failed ({result.returncode}): {' '.join(command)}: "
                          f"{result.stdout.strip()}")
        return result.stdout

    def query(self, name: str) -> Any:
        if name not in {
            "clients", "workspaces", "monitors", "activeworkspace",
            "activewindow", "workspacerules",
        }:
            raise ValueError(f"unsupported hyprctl query: {name}")
        return json.loads(self._run(["hyprctl", name, "-j"]))

    def _eval(self, source: str) -> None:
        self._run(["hyprctl", "eval", source])

    def dispatch_window(self, address: str, workspace_id: int) -> None:
        if not re.fullmatch(r"0x[0-9a-f]+", address, re.IGNORECASE):
            raise ValueError(f"invalid window address: {address!r}")
        if not valid_workspace_id(workspace_id):
            raise ValueError(f"invalid workspace id: {workspace_id!r}")
        self._eval(
            "hl.dispatch(hl.dsp.window.move({workspace = "
            f"'{workspace_id}', follow = false, window = 'address:{address}'}}))"
        )

    def move_workspace(self, workspace_id: int, monitor: str) -> None:
        self._validate_monitor(monitor)
        if not valid_workspace_id(workspace_id):
            raise ValueError(f"invalid workspace id: {workspace_id!r}")
        self._eval(
            "hl.dispatch(hl.dsp.workspace.move({workspace = "
            f"'{workspace_id}', monitor = '{monitor}'}}))"
        )

    def focus_workspace(self, workspace_id: int, monitor: str) -> None:
        self._validate_monitor(monitor)
        if not valid_workspace_id(workspace_id):
            raise ValueError(f"invalid workspace id: {workspace_id!r}")
        self._eval(
            f"hl.dispatch(hl.dsp.focus({{monitor = '{monitor}'}})); "
            f"hl.dispatch(hl.dsp.focus({{workspace = '{workspace_id}'}}))"
        )

    def focus_window(self, address: str) -> None:
        if not re.fullmatch(r"0x[0-9a-f]+", address, re.IGNORECASE):
            raise ValueError(f"invalid window address: {address!r}")
        self._eval(f"hl.dispatch(hl.dsp.focus({{window = 'address:{address}'}}))")

    def reload_config(self) -> None:
        self._run(["hyprctl", "reload"])

    def config_errors(self) -> str:
        return self._run(["hyprctl", "configerrors"]).strip()

    def validate_lua(self, payload: bytes) -> None:
        descriptor, name = tempfile.mkstemp(prefix="workspace-reorder-", suffix=".lua")
        path = pathlib.Path(name)
        try:
            with os.fdopen(descriptor, "wb") as stream:
                stream.write(payload)
            self._run(["luac", "-p", str(path)])
        finally:
            path.unlink(missing_ok=True)

    @staticmethod
    def _validate_monitor(monitor: str) -> None:
        if not re.fullmatch(r"[A-Za-z0-9_.:-]+", monitor):
            raise ValueError(f"invalid monitor name: {monitor!r}")


def capture_snapshot(adapter: Any) -> LiveSnapshot:
    return LiveSnapshot(
        clients=adapter.query("clients"),
        workspaces=adapter.query("workspaces"),
        monitors=adapter.query("monitors"),
        active_workspace=adapter.query("activeworkspace"),
        active_window=adapter.query("activewindow"),
        workspace_rules=adapter.query("workspacerules"),
    )


_REQUIRE = re.compile(rb"\brequire\s*\(?\s*[\"']([A-Za-z0-9_.-]+)[\"']\s*\)?")


def _sha256(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def load_config_snapshot(
    entrypoint: pathlib.Path, rules_path: pathlib.Path
) -> ConfigSnapshot:
    entrypoint = pathlib.Path(entrypoint).resolve()
    rules_path = pathlib.Path(rules_path).resolve()
    if not entrypoint.is_file():
        raise ValueError(f"Hyprland Lua entrypoint does not exist: {entrypoint}")
    root = entrypoint.parent
    pending = [entrypoint]
    sources = {}
    while pending:
        path = pending.pop()
        key = str(path)
        if key in sources:
            continue
        payload = path.read_bytes()
        sources[key] = payload
        for module in _REQUIRE.findall(payload):
            relative = module.decode("utf-8").replace(".", "/") + ".lua"
            dependency = (root / relative).resolve()
            if dependency.is_relative_to(root) and dependency.is_file():
                pending.append(dependency)
    if str(rules_path) not in sources:
        raise ValueError("rules.lua is not in the active local require dependency closure")
    return ConfigSnapshot(
        entrypoint=entrypoint,
        rules_path=rules_path,
        rules_bytes=sources[str(rules_path)],
        dependency_hashes={key: _sha256(value) for key, value in sources.items()},
        dependency_sources=sources,
    )


def _validate_dependency_hashes(config: ConfigSnapshot) -> None:
    for name, expected in config.dependency_hashes.items():
        path = pathlib.Path(name)
        if not path.is_file() or _sha256(path.read_bytes()) != expected:
            raise ValueError(f"configuration dependency changed: {path}")


def _metadata_object(payload: bytes) -> dict[str, Any]:
    try:
        value = json.loads(payload.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ValueError(f"invalid metadata JSON: {error}") from error
    if not isinstance(value, dict) or value.get("version") != SCHEMA_VERSION:
        raise ValueError("workspace reordering requires schema-2 metadata")
    if not isinstance(value.get("order"), list) or not isinstance(value.get("names", {}), dict):
        raise ValueError("invalid schema-2 metadata shape")
    return value


def _expected_client_map(request: dict[str, Any]) -> dict[str, int]:
    rows = request.get("expectedClients")
    if not isinstance(rows, list):
        raise ValueError("request expectedClients must be an array")
    result = {}
    for row in rows:
        if not isinstance(row, dict):
            raise ValueError("invalid expected client row")
        address = row.get("address")
        workspace_id = row.get("workspaceId")
        if not isinstance(address, str) or not valid_workspace_id(workspace_id):
            raise ValueError("invalid expected client membership")
        if address in result:
            raise ValueError("duplicate expected client address")
        result[address] = workspace_id
    return result


def _current_client_map(clients: list[dict[str, Any]]) -> dict[str, int]:
    result = {}
    for client in clients:
        workspace_id = client.get("workspace", {}).get("id")
        address = client.get("address")
        if valid_workspace_id(workspace_id) and isinstance(address, str):
            result[address] = workspace_id
    return result


def _validate_client_state(client: dict[str, Any]) -> None:
    supported = (
        isinstance(client.get("floating"), bool)
        and client.get("pseudo") in (None, True, False)
        and client.get("fullscreen") in (0, 1, 2, 3)
        and client.get("fullscreenClient", 0) in (0, 1, 2, 3)
        and client.get("grouped", []) == []
        and client.get("swallowing") in (None, "", "0x0")
        and client.get("pinned", False) is False
    )
    if not supported:
        raise ValueError(
            f"unsupported window state for {client.get('address', '<unknown>')}"
        )


def _selector_may_affect(selector: str, affected: set[int]) -> bool:
    if selector.isdigit():
        return int(selector) in affected
    for start, end in re.findall(r"r\[(\d+)-(\d+)\]", selector):
        low, high = sorted((int(start), int(end)))
        if any(low <= workspace_id <= high for workspace_id in affected):
            return True
    return True


def _validate_workspace_rules(
    rules: list[dict[str, Any]], affected: set[int]
) -> set[int]:
    exact_ids = set()
    for rule in rules:
        selector = str(
            rule.get("workspaceString")
            or rule.get("workspaceId")
            or rule.get("workspaceName")
            or ""
        )
        if selector.isdigit():
            exact_ids.add(int(selector))
        monitor = rule.get("monitor")
        persistent = rule.get("persistent") or rule.get("isPersistent")
        if (monitor not in (None, "") or bool(persistent)) \
                and _selector_may_affect(selector, affected):
            raise ValueError(f"unsafe workspace rule for affected mapping: {selector}")
    return exact_ids


def _validate_other_config_rules(config: ConfigSnapshot, affected: set[int]) -> None:
    numeric_effect = re.compile(rb"\bworkspace\s*=\s*[\"']?(\d+)")
    for name, payload in config.dependency_sources.items():
        if pathlib.Path(name) == config.rules_path:
            continue
        if b"hl.window_rule" not in payload:
            continue
        for match in numeric_effect.finditer(payload):
            if int(match.group(1)) in affected:
                raise ValueError(
                    f"affected workspace assignment exists outside workspace_windows: {name}"
                )


def preflight(
    request: dict[str, Any],
    snapshot: LiveSnapshot,
    metadata: bytes,
    config: ConfigSnapshot,
    metadata_path: pathlib.Path | None = None,
) -> TransactionPlan:
    _validate_dependency_hashes(config)
    if request.get("version") != 1:
        raise ValueError("unsupported reorder request version")
    metadata_object = _metadata_object(metadata)
    slot_order = request.get("slotOrder")
    identity_order = request.get("identityOrder")
    mapping = build_permutation(slot_order, identity_order)
    live_ids = [
        workspace.get("id") for workspace in snapshot.workspaces
        if valid_workspace_id(workspace.get("id"))
    ]
    expected_slots = canonical_slots(list(metadata_object["order"]) + live_ids)
    if slot_order != expected_slots:
        raise ValueError("request workspace slots no longer match live metadata")
    if _expected_client_map(request) != _current_client_map(snapshot.clients):
        raise ValueError("client membership changed since drag start")

    affected = set(mapping) | set(mapping.values())
    exact_rule_ids = _validate_workspace_rules(snapshot.workspace_rules, affected)
    _validate_other_config_rules(config, affected)
    rewrite = rewrite_workspace_windows(config.rules_bytes, mapping)

    clients_by_source = {}
    for client in snapshot.clients:
        workspace_id = client.get("workspace", {}).get("id")
        if workspace_id not in mapping:
            continue
        _validate_client_state(client)
        clients_by_source.setdefault(workspace_id, []).append(client)
    for clients in clients_by_source.values():
        clients.sort(key=lambda client: client["address"])

    forbidden = set(slot_order) | set(live_ids) | exact_rule_ids
    source_ids_with_clients = sorted(clients_by_source)
    temporary_ids = allocate_temporary_ids(len(source_ids_with_clients), forbidden)
    temporary_by_source = dict(zip(source_ids_with_clients, temporary_ids, strict=True))

    workspace_by_id = {
        workspace["id"]: workspace for workspace in snapshot.workspaces
        if valid_workspace_id(workspace.get("id"))
    }
    monitor_by_source = {
        source_id: str(workspace_by_id[source_id].get("monitor", ""))
        for source_id in mapping
        if source_id in workspace_by_id and workspace_by_id[source_id].get("monitor")
    }
    focus_by_monitor = {}
    focused_monitor = ""
    for monitor in snapshot.monitors:
        monitor_name = str(monitor.get("name", ""))
        active_id = monitor.get("activeWorkspace", {}).get("id")
        if monitor_name and valid_workspace_id(active_id):
            focus_by_monitor[monitor_name] = mapping.get(active_id, active_id)
        if monitor.get("focused") is True:
            focused_monitor = monitor_name

    return TransactionPlan(
        request=request,
        slot_order=list(slot_order),
        identity_order=list(identity_order),
        mapping=mapping,
        clients_by_source=clients_by_source,
        temporary_by_source=temporary_by_source,
        monitor_by_source=monitor_by_source,
        focus_by_monitor=focus_by_monitor,
        focused_monitor=focused_monitor,
        focused_window=str(snapshot.active_window.get("address", "")),
        rule_bytes=rewrite.bytes,
        rule_rows=rewrite.rows,
        metadata_bytes=metadata,
        metadata_path=(pathlib.Path(metadata_path).resolve()
                       if metadata_path is not None else None),
        config=config,
        snapshot=snapshot,
    )


_CLIENT_STATE_FIELDS = (
    "monitor", "floating", "pseudo", "fullscreen", "fullscreenClient",
    "grouped", "swallowing", "pinned",
)


def _captured_client_state(client: dict[str, Any]) -> dict[str, Any]:
    return {name: client.get(name) for name in _CLIENT_STATE_FIELDS}


def _timestamp() -> str:
    return datetime.datetime.now(datetime.UTC).strftime("%Y%m%dT%H%M%S%fZ")


def _fsync_directory(path: pathlib.Path) -> None:
    descriptor = os.open(path, os.O_RDONLY | getattr(os, "O_DIRECTORY", 0))
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def _atomic_write_bytes(path: pathlib.Path, payload: bytes) -> None:
    path = pathlib.Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    mode = path.stat().st_mode & 0o777 if path.exists() else 0o600
    descriptor, name = tempfile.mkstemp(prefix=f".{path.name}.write-", dir=path.parent)
    temporary = pathlib.Path(name)
    try:
        os.fchmod(descriptor, mode)
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(payload)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
        _fsync_directory(path.parent)
    except Exception:
        temporary.unlink(missing_ok=True)
        raise


def _journal_write(path: pathlib.Path, journal: dict[str, Any]) -> None:
    payload = (json.dumps(journal, ensure_ascii=False, indent=2, sort_keys=True)
               + "\n").encode("utf-8")
    _atomic_write_bytes(path, payload)


def _metadata_candidate(plan: TransactionPlan) -> bytes:
    metadata = _metadata_object(plan.metadata_bytes)
    names = dict(metadata.get("names", {}))
    for destination in plan.mapping.values():
        names.pop(str(destination), None)
    original_names = metadata.get("names", {})
    for source, destination in plan.mapping.items():
        if str(source) in original_names:
            names[str(destination)] = original_names[str(source)]
    metadata["names"] = names
    metadata["order"] = canonical_slots(plan.slot_order)
    return (json.dumps(metadata, ensure_ascii=False, indent=2) + "\n").encode("utf-8")


def _original_focus_by_monitor(plan: TransactionPlan) -> dict[str, int]:
    result = {}
    for monitor in plan.snapshot.monitors:
        name = monitor.get("name")
        workspace_id = monitor.get("activeWorkspace", {}).get("id")
        if isinstance(name, str) and name and valid_workspace_id(workspace_id):
            result[name] = workspace_id
    return result


def _plan_client_rows(plan: TransactionPlan) -> list[dict[str, Any]]:
    rows = []
    for source, clients in sorted(plan.clients_by_source.items()):
        for client in clients:
            rows.append({
                "address": client["address"],
                "source": source,
                "temporary": plan.temporary_by_source[source],
                "destination": plan.mapping[source],
                "state": _captured_client_state(client),
            })
    return rows


def _create_journal(plan: TransactionPlan, baseline_errors: str) -> pathlib.Path:
    assert plan.metadata_path is not None
    root = plan.metadata_path.parent / "hyprland-overview-reorder-transactions"
    directory = root / _timestamp()
    directory.mkdir(parents=True, exist_ok=False)
    _fsync_directory(root)
    metadata_backup = directory / "metadata.before"
    rules_backup = directory / "rules.lua.before"
    _atomic_write_bytes(metadata_backup, plan.metadata_bytes)
    _atomic_write_bytes(rules_backup, plan.config.rules_bytes)
    if (metadata_backup.read_bytes() != plan.metadata_bytes
            or rules_backup.read_bytes() != plan.config.rules_bytes):
        raise OSError("transaction backup verification failed")
    journal_path = directory / "journal.json"
    journal = {
        "version": 1,
        "status": "prepared",
        "message": "transaction prepared; no movement recorded",
        "metadataPath": str(plan.metadata_path),
        "rulesPath": str(plan.config.rules_path),
        "metadataSha256": _sha256(plan.metadata_bytes),
        "rulesSha256": _sha256(plan.config.rules_bytes),
        "baselineConfigErrors": baseline_errors,
        "mapping": {str(key): value for key, value in plan.mapping.items()},
        "monitorBySource": {
            str(key): value for key, value in plan.monitor_by_source.items()
        },
        "clients": _plan_client_rows(plan),
        "focusByMonitor": _original_focus_by_monitor(plan),
        "focusedMonitor": plan.focused_monitor,
        "focusedWindow": plan.focused_window,
    }
    _journal_write(journal_path, journal)
    return journal_path


def _update_journal(
    journal_path: pathlib.Path, status: str, message: str
) -> None:
    journal = json.loads(journal_path.read_text(encoding="utf-8"))
    journal["status"] = status
    journal["message"] = message
    _journal_write(journal_path, journal)


def _unresolved_journal(metadata_path: pathlib.Path) -> pathlib.Path | None:
    root = metadata_path.parent / "hyprland-overview-reorder-transactions"
    if not root.is_dir():
        return None
    for path in sorted(root.glob("*/journal.json")):
        try:
            status = json.loads(path.read_text(encoding="utf-8")).get("status")
        except (OSError, json.JSONDecodeError):
            return path
        if status not in {"success", "recovered"}:
            return path
    return None


def _assert_current_preconditions(plan: TransactionPlan, adapter: Any) -> str:
    assert plan.metadata_path is not None
    if plan.metadata_path.read_bytes() != plan.metadata_bytes:
        raise ValueError("metadata changed after preflight")
    _validate_dependency_hashes(plan.config)
    current = capture_snapshot(adapter)
    if _current_client_map(current.clients) != _current_client_map(plan.snapshot.clients):
        raise ValueError("client membership changed after preflight")
    if current.workspace_rules != plan.snapshot.workspace_rules:
        raise ValueError("workspace rules changed after preflight")
    workspace_fields = ("id", "name", "monitor", "monitorID", "ispersistent")
    current_workspaces = sorted(
        tuple(workspace.get(field) for field in workspace_fields)
        for workspace in current.workspaces
    )
    planned_workspaces = sorted(
        tuple(workspace.get(field) for field in workspace_fields)
        for workspace in plan.snapshot.workspaces
    )
    if current_workspaces != planned_workspaces:
        raise ValueError("workspace assignments changed after preflight")
    monitor_fields = ("id", "name", "focused", "activeWorkspace")
    current_monitors = [
        tuple(json.dumps(monitor.get(field), sort_keys=True) for field in monitor_fields)
        for monitor in current.monitors
    ]
    planned_monitors = [
        tuple(json.dumps(monitor.get(field), sort_keys=True) for field in monitor_fields)
        for monitor in plan.snapshot.monitors
    ]
    if current_monitors != planned_monitors:
        raise ValueError("monitor focus or workspace assignment changed after preflight")
    for client in current.clients:
        address = client.get("address")
        original = next(
            (item for item in plan.snapshot.clients if item.get("address") == address),
            None,
        )
        if original is not None and _captured_client_state(client) != _captured_client_state(original):
            raise ValueError(f"client state changed after preflight: {address}")
    adapter.validate_lua(plan.rule_bytes)
    return adapter.config_errors()


def _verify_positions(
    plan: TransactionPlan,
    adapter: Any,
    expected: dict[str, int],
) -> None:
    current_clients = adapter.query("clients")
    current_map = _current_client_map(current_clients)
    original_map = _current_client_map(plan.snapshot.clients)
    if set(current_map) != set(original_map):
        raise RuntimeError("client set changed during workspace transaction")
    captured = {
        client["address"]: client
        for clients in plan.clients_by_source.values()
        for client in clients
    }
    for address, workspace_id in expected.items():
        if current_map.get(address) != workspace_id:
            raise RuntimeError(
                f"window {address} is on workspace {current_map.get(address)}, "
                f"expected {workspace_id}"
            )
    for address, workspace_id in original_map.items():
        if address not in captured and current_map.get(address) != workspace_id:
            raise RuntimeError(f"unrelated window moved: {address}")
    by_address = {client.get("address"): client for client in current_clients}
    for address, original in captured.items():
        if _captured_client_state(by_address[address]) != _captured_client_state(original):
            raise RuntimeError(f"window state changed during transaction: {address}")


def _restore_focus(
    adapter: Any,
    focus_by_monitor: dict[str, int],
    focused_monitor: str,
    focused_window: str,
) -> None:
    for monitor, workspace_id in sorted(focus_by_monitor.items()):
        adapter.focus_workspace(workspace_id, monitor)
    if focused_monitor and focused_monitor in focus_by_monitor:
        adapter.focus_workspace(focus_by_monitor[focused_monitor], focused_monitor)
    if focused_window:
        addresses = {client.get("address") for client in adapter.query("clients")}
        if focused_window in addresses:
            adapter.focus_window(focused_window)
    monitors = adapter.query("monitors")
    active_by_monitor = {
        str(monitor.get("name", "")): monitor.get("activeWorkspace", {}).get("id")
        for monitor in monitors
    }
    for monitor, workspace_id in focus_by_monitor.items():
        if active_by_monitor.get(monitor) != workspace_id:
            raise RuntimeError(
                f"focus restoration did not select workspace {workspace_id} on {monitor}"
            )
    if focused_monitor:
        actual_focused = next(
            (str(monitor.get("name", "")) for monitor in monitors
             if monitor.get("focused") is True),
            "",
        )
        if actual_focused != focused_monitor:
            raise RuntimeError(
                f"focus restoration selected monitor {actual_focused}, "
                f"expected {focused_monitor}"
            )
    if focused_window:
        addresses = {client.get("address") for client in adapter.query("clients")}
        if focused_window in addresses:
            active_window = adapter.query("activewindow")
            if active_window.get("address") != focused_window:
                raise RuntimeError(
                    f"focus restoration did not select window {focused_window}"
                )


def _validate_config_bytes(
    config: ConfigSnapshot, expected_rules: bytes
) -> None:
    for name, expected_hash in config.dependency_hashes.items():
        path = pathlib.Path(name)
        if path == config.rules_path:
            expected_hash = _sha256(expected_rules)
        if not path.is_file() or _sha256(path.read_bytes()) != expected_hash:
            raise RuntimeError(f"configuration dependency changed: {path}")


def _recover_plan(
    plan: TransactionPlan,
    adapter: Any,
    journal_path: pathlib.Path,
    baseline_errors: str,
    cause: Exception,
) -> TransactionResult:
    errors = []
    for source, clients in sorted(plan.clients_by_source.items()):
        for client in clients:
            address = client["address"]
            try:
                current = _current_client_map(adapter.query("clients"))
                if address in current and current[address] != source:
                    adapter.dispatch_window(address, source)
            except Exception as error:  # recovery deliberately continues
                errors.append(f"window {address}: {error}")
    try:
        assert plan.metadata_path is not None
        _atomic_write_bytes(plan.config.rules_path, plan.config.rules_bytes)
        _atomic_write_bytes(plan.metadata_path, plan.metadata_bytes)
    except Exception as error:
        errors.append(f"file restore: {error}")
    try:
        adapter.reload_config()
        if adapter.config_errors() != baseline_errors:
            raise RuntimeError("configuration errors differ from pre-transaction state")
        _validate_config_bytes(plan.config, plan.config.rules_bytes)
    except Exception as error:
        errors.append(f"configuration restore: {error}")
    try:
        _restore_focus(
            adapter, _original_focus_by_monitor(plan), plan.focused_monitor,
            plan.focused_window,
        )
    except Exception as error:
        errors.append(f"focus restore: {error}")
    try:
        expected = {
            client["address"]: source
            for source, clients in plan.clients_by_source.items()
            for client in clients
        }
        _verify_positions(plan, adapter, expected)
        if (plan.metadata_path is None
                or plan.metadata_path.read_bytes() != plan.metadata_bytes
                or plan.config.rules_path.read_bytes() != plan.config.rules_bytes):
            raise RuntimeError("restored files do not match transaction backups")
    except Exception as error:
        errors.append(f"recovery verification: {error}")
    if errors:
        message = (f"transaction failed ({cause}); recovery is incomplete and not atomic: "
                   + "; ".join(errors))
        status = "recovery_incomplete"
    else:
        message = f"transaction failed ({cause}); verified best-effort recovery completed"
        status = "recovered"
    try:
        _update_journal(journal_path, status, message)
    except Exception as error:
        message += f"; journal update failed: {error}"
        status = "recovery_incomplete"
    return TransactionResult(status, message, journal_path, True)


def execute(plan: TransactionPlan, adapter: Any) -> TransactionResult:
    """Execute an already approved plan, recovering on any post-journal failure."""

    if plan.metadata_path is None:
        return TransactionResult(
            "refused", "transaction plan has no metadata path", None, False
        )
    lock_path = plan.metadata_path.with_name(f"{plan.metadata_path.name}.reorder.lock")
    lock_path.parent.mkdir(parents=True, exist_ok=True)
    with lock_path.open("a+b") as lock_stream:
        fcntl.flock(lock_stream.fileno(), fcntl.LOCK_EX)
        unresolved = _unresolved_journal(plan.metadata_path)
        if unresolved is not None:
            return TransactionResult(
                "refused", f"unresolved prior transaction: {unresolved}", None, False
            )
        try:
            baseline_errors = _assert_current_preconditions(plan, adapter)
        except (OSError, ValueError, RuntimeError) as error:
            return TransactionResult("refused", str(error), None, False)

        journal_path: pathlib.Path | None = None
        try:
            journal_path = _create_journal(plan, baseline_errors)
            expected = _current_client_map(plan.snapshot.clients)
            for source, clients in sorted(plan.clients_by_source.items()):
                temporary = plan.temporary_by_source[source]
                for client in clients:
                    adapter.dispatch_window(client["address"], temporary)
                    expected[client["address"]] = temporary
                monitor = plan.monitor_by_source.get(source)
                if monitor:
                    adapter.move_workspace(temporary, monitor)
                _verify_positions(plan, adapter, expected)
            _update_journal(journal_path, "phase1", "all captured windows verified on temporary workspaces")

            for source, destination in sorted(plan.mapping.items()):
                monitor = plan.monitor_by_source.get(source)
                if monitor:
                    adapter.move_workspace(destination, monitor)
            for source, clients in sorted(plan.clients_by_source.items()):
                destination = plan.mapping[source]
                for client in clients:
                    adapter.dispatch_window(client["address"], destination)
                    expected[client["address"]] = destination
                _verify_positions(plan, adapter, expected)
            _update_journal(journal_path, "phase2", "all captured windows verified on final workspaces")

            metadata_candidate = _metadata_candidate(plan)
            _atomic_write_bytes(plan.config.rules_path, plan.rule_bytes)
            _atomic_write_bytes(plan.metadata_path, metadata_candidate)
            _update_journal(journal_path, "files_committed", "rules and metadata committed")
            adapter.reload_config()
            if adapter.config_errors() != baseline_errors:
                raise RuntimeError("Hyprland reported new configuration errors")
            _validate_config_bytes(plan.config, plan.rule_bytes)
            if plan.metadata_path.read_bytes() != metadata_candidate:
                raise RuntimeError("metadata changed after commit")
            _restore_focus(
                adapter, plan.focus_by_monitor, plan.focused_monitor,
                plan.focused_window,
            )
            _verify_positions(plan, adapter, expected)
            _update_journal(journal_path, "success", "transaction completed and verified")
            return TransactionResult(
                "success", "workspace content reorder completed", journal_path, True
            )
        except Exception as error:
            if journal_path is None:
                return TransactionResult("refused", str(error), None, False)
            return _recover_plan(plan, adapter, journal_path, baseline_errors, error)


def recover(journal_path: pathlib.Path, adapter: Any) -> TransactionResult:
    """Attempt explicit, verified recovery from a durable transaction journal."""

    journal_path = pathlib.Path(journal_path).resolve()
    try:
        journal = json.loads(journal_path.read_text(encoding="utf-8"))
        if journal.get("version") != 1:
            raise ValueError("unsupported transaction journal version")
        if journal.get("status") in {"success", "recovered"}:
            return TransactionResult(
                "refused", "transaction journal is already resolved",
                journal_path, False,
            )
        metadata_path = pathlib.Path(journal["metadataPath"]).resolve()
        rules_path = pathlib.Path(journal["rulesPath"]).resolve()
        metadata_backup = journal_path.parent / "metadata.before"
        rules_backup = journal_path.parent / "rules.lua.before"
        metadata_bytes = metadata_backup.read_bytes()
        rules_bytes = rules_backup.read_bytes()
        if _sha256(metadata_bytes) != journal.get("metadataSha256"):
            raise ValueError("metadata recovery backup hash mismatch")
        if _sha256(rules_bytes) != journal.get("rulesSha256"):
            raise ValueError("rules.lua recovery backup hash mismatch")
        client_rows = journal.get("clients")
        focus_by_monitor = journal.get("focusByMonitor")
        if not isinstance(client_rows, list) or not isinstance(focus_by_monitor, dict):
            raise ValueError("invalid recovery journal shape")
    except (OSError, KeyError, TypeError, ValueError, json.JSONDecodeError) as error:
        return TransactionResult("refused", str(error), journal_path, False)

    lock_path = metadata_path.with_name(f"{metadata_path.name}.reorder.lock")
    errors = []
    with lock_path.open("a+b") as lock_stream:
        fcntl.flock(lock_stream.fileno(), fcntl.LOCK_EX)
        for row in client_rows:
            try:
                address = row["address"]
                source = row["source"]
                current = _current_client_map(adapter.query("clients"))
                if address not in current:
                    raise RuntimeError("captured window no longer exists")
                if current[address] != source:
                    adapter.dispatch_window(address, source)
            except Exception as error:  # recovery deliberately continues
                errors.append(f"window {row.get('address', '<unknown>')}: {error}")
        try:
            _atomic_write_bytes(rules_path, rules_bytes)
            _atomic_write_bytes(metadata_path, metadata_bytes)
        except Exception as error:
            errors.append(f"file restore: {error}")
        try:
            adapter.reload_config()
            if adapter.config_errors() != journal.get("baselineConfigErrors", ""):
                raise RuntimeError("configuration errors differ from pre-transaction state")
        except Exception as error:
            errors.append(f"configuration restore: {error}")
        try:
            normalized_focus = {
                str(monitor): int(workspace_id)
                for monitor, workspace_id in focus_by_monitor.items()
            }
            _restore_focus(
                adapter, normalized_focus, str(journal.get("focusedMonitor", "")),
                str(journal.get("focusedWindow", "")),
            )
        except Exception as error:
            errors.append(f"focus restore: {error}")
        try:
            current_clients = {
                client.get("address"): client for client in adapter.query("clients")
            }
            for row in client_rows:
                address = row["address"]
                client = current_clients.get(address)
                if client is None or client.get("workspace", {}).get("id") != row["source"]:
                    raise RuntimeError(f"workspace recovery did not verify for {address}")
                if _captured_client_state(client) != row["state"]:
                    raise RuntimeError(f"window-state recovery did not verify for {address}")
            if metadata_path.read_bytes() != metadata_bytes:
                raise RuntimeError("metadata recovery did not verify")
            if rules_path.read_bytes() != rules_bytes:
                raise RuntimeError("rules.lua recovery did not verify")
        except Exception as error:
            errors.append(f"recovery verification: {error}")

        if errors:
            status = "recovery_incomplete"
            message = "recovery is incomplete and not atomic: " + "; ".join(errors)
        else:
            status = "recovered"
            message = "explicit best-effort recovery completed and verified"
        try:
            _update_journal(journal_path, status, message)
        except Exception as error:
            status = "recovery_incomplete"
            message += f"; journal update failed: {error}"
        return TransactionResult(status, message, journal_path, True)


def inspect_request(
    request: dict[str, Any],
    snapshot: LiveSnapshot,
    metadata: bytes,
    config: ConfigSnapshot,
) -> dict[str, Any]:
    plan = preflight(request, snapshot, metadata, config)
    return {
        "version": 1,
        "status": "ready",
        "mapping": {str(key): value for key, value in plan.mapping.items()},
        "temporaryIds": {
            str(key): value for key, value in plan.temporary_by_source.items()
        },
        "clients": {
            str(key): [
                {
                    "address": client["address"],
                    "title": client.get("title", ""),
                    "class": client.get("class", ""),
                    "destination": plan.mapping[key],
                }
                for client in clients
            ]
            for key, clients in plan.clients_by_source.items()
        },
        "ruleRows": plan.rule_rows,
        "monitorBySource": {
            str(key): value for key, value in plan.monitor_by_source.items()
        },
        "focusByMonitor": plan.focus_by_monitor,
        "focusedMonitor": plan.focused_monitor,
        "focusedWindow": plan.focused_window,
        "metadataSha256": _sha256(metadata),
        "rulesSha256": _sha256(config.rules_bytes),
    }


def _default_config_entrypoint() -> pathlib.Path:
    configured = os.environ.get("HYPRLAND_CONFIG")
    return pathlib.Path(configured) if configured else pathlib.Path.home() / ".config/hypr/hyprland.lua"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)
    migrate = subparsers.add_parser("migrate-metadata")
    migrate.add_argument("--metadata", required=True, type=pathlib.Path)
    inspect_parser = subparsers.add_parser("inspect")
    inspect_parser.add_argument("--metadata", required=True, type=pathlib.Path)
    inspect_parser.add_argument("--rules", required=True, type=pathlib.Path)
    inspect_parser.add_argument("--request", required=True, type=pathlib.Path)
    inspect_parser.add_argument("--config", type=pathlib.Path,
                                default=_default_config_entrypoint())
    apply_parser = subparsers.add_parser("apply")
    apply_parser.add_argument("--metadata", required=True, type=pathlib.Path)
    apply_parser.add_argument("--rules", required=True, type=pathlib.Path)
    apply_parser.add_argument("--request", required=True, type=pathlib.Path)
    apply_parser.add_argument("--config", type=pathlib.Path,
                              default=_default_config_entrypoint())
    apply_parser.add_argument("--confirm-live-reorder", action="store_true")
    recover_parser = subparsers.add_parser("recover")
    recover_parser.add_argument("--journal", required=True, type=pathlib.Path)
    recover_parser.add_argument("--confirm-recovery", action="store_true")
    args = parser.parse_args(argv)

    try:
        if args.command == "migrate-metadata":
            result = migrate_metadata(args.metadata)
        elif args.command == "inspect":
            request = json.loads(args.request.read_text(encoding="utf-8"))
            snapshot = capture_snapshot(HyprctlAdapter())
            config = load_config_snapshot(args.config, args.rules)
            result = inspect_request(
                request, snapshot, args.metadata.read_bytes(), config
            )
        elif args.command == "apply":
            if not args.confirm_live_reorder:
                raise ValueError("apply requires --confirm-live-reorder")
            request = json.loads(args.request.read_text(encoding="utf-8"))
            snapshot = capture_snapshot(HyprctlAdapter())
            config = load_config_snapshot(args.config, args.rules)
            plan = preflight(
                request, snapshot, args.metadata.read_bytes(), config,
                metadata_path=args.metadata,
            )
            transaction = execute(plan, HyprctlAdapter())
            result = {
                "version": 1,
                "status": transaction.status,
                "message": transaction.message,
                "changed": transaction.changed,
                "journal": (str(transaction.journal_path)
                            if transaction.journal_path is not None else None),
            }
            if transaction.status != "success":
                print(json.dumps(result, separators=(",", ":")))
                return 1
        elif args.command == "recover":
            if not args.confirm_recovery:
                raise ValueError("recover requires --confirm-recovery")
            transaction = recover(args.journal, HyprctlAdapter())
            result = {
                "version": 1,
                "status": transaction.status,
                "message": transaction.message,
                "changed": transaction.changed,
                "journal": (str(transaction.journal_path)
                            if transaction.journal_path is not None else None),
            }
            if transaction.status != "recovered":
                print(json.dumps(result, separators=(",", ":")))
                return 1
        else:  # pragma: no cover - argparse prevents this path
            raise ValueError(f"unsupported command: {args.command}")
    except (OSError, ValueError) as error:
        print(json.dumps({
            "version": 1,
            "status": "error",
            "message": str(error),
        }, separators=(",", ":")))
        return 1

    print(json.dumps(result, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
