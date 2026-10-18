// Persistent desktop presentation metadata.
//
// Hyprland workspace IDs remain the only backend identity. Names and order are
// normalized presentation data so corrupt state cannot remove or duplicate a
// workspace.
//
// The classic strip always offers workspaces 1-10, but that default set is not
// an upper bound: every positive integer ID Hyprland reports (or the user
// persists with custom metadata) is an ordinary desktop without a fixed limit.

var SCHEMA_VERSION = 2;
var LEGACY_SCHEMA_VERSION = 1;
var MIN_WORKSPACE_ID = 1;
// Always-present classic desktops, never a maximum workspace ID.
var DEFAULT_WORKSPACES = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];

function defaultName(workspaceId) {
    return `Desktop ${workspaceId}`;
}

// Ordinary desktop IDs are positive integers. Special Hyprland workspaces
// report non-ordinary identifiers and never enter the metadata model.
function validWorkspaceId(value) {
    const number = Number(value);
    return Number.isInteger(number) && number >= MIN_WORKSPACE_ID;
}

function collectIds(values, order, seen) {
    if (!Array.isArray(values))
        return;
    values.forEach(candidate => {
        if (!validWorkspaceId(candidate))
            return;
        const workspaceId = Number(candidate);
        if (seen[workspaceId])
            return;
        seen[workspaceId] = true;
        order.push(workspaceId);
    });
}

function sanitizeName(value, workspaceId) {
    if (typeof value !== "string")
        return defaultName(workspaceId);
    const trimmed = value.trim();
    return trimmed.length > 0 ? trimmed : defaultName(workspaceId);
}

// reportedWorkspaceIds optionally carries live Hyprland IDs so a persisted
// order and the running desktop set merge without mutating either source.
function sanitizeOrder(value, reportedWorkspaceIds) {
    const order = [];
    const seen = {};
    collectIds(DEFAULT_WORKSPACES, order, seen);
    collectIds(value, order, seen);
    collectIds(reportedWorkspaceIds, order, seen);
    return order.sort((a, b) => a - b);
}

function collectExtras(source) {
    const extras = {};
    if (!source || typeof source !== "object" || Array.isArray(source))
        return extras;
    if (source.extras && typeof source.extras === "object"
            && !Array.isArray(source.extras)) {
        Object.keys(source.extras).forEach(key => {
            extras[key] = source.extras[key];
        });
    }
    Object.keys(source).forEach(key => {
        if (!["version", "names", "order", "entries", "extras"].includes(key))
            extras[key] = source[key];
    });
    return extras;
}

function normalize(raw) {
    const source = raw && typeof raw === "object"
        && (raw.version === SCHEMA_VERSION
            || raw.version === LEGACY_SCHEMA_VERSION) ? raw : {};
    const names = source.names && typeof source.names === "object"
        && !Array.isArray(source.names) ? source.names : {};
    const order = sanitizeOrder(
        (Array.isArray(source.order) ? source.order : []).concat(Object.keys(names)));
    const entries = order.map(workspaceId => ({
        workspaceId: workspaceId,
        name: sanitizeName(names[`${workspaceId}`], workspaceId)
    }));
    return {
        version: SCHEMA_VERSION,
        order: order,
        entries: entries,
        extras: collectExtras(source)
    };
}

// Presentation-only merge used by live views: persisted state plus the
// workspaces Hyprland currently reports. Nothing here is written to disk on its
// own; persistence only happens through an explicit user action.
function mergeReported(state, reportedWorkspaceIds) {
    const source = stateToSchema(state);
    return normalize({
        version: SCHEMA_VERSION,
        names: source.names,
        order: sanitizeOrder(source.order, reportedWorkspaceIds),
        extras: collectExtras(source)
    });
}

function rename(state, workspaceId, name) {
    const current = normalize(stateToSchema(state));
    if (!validWorkspaceId(workspaceId))
        return current;
    const wantedId = Number(workspaceId);
    let present = false;
    const nextEntries = current.entries.map(entry => {
        if (entry.workspaceId === wantedId)
            present = true;
        return {
            workspaceId: entry.workspaceId,
            name: entry.workspaceId === wantedId
                ? sanitizeName(name, wantedId) : entry.name
        };
    });
    let order = current.order.slice();
    if (!present) {
        nextEntries.push({ workspaceId: wantedId, name: sanitizeName(name, wantedId) });
        order = order.concat(wantedId);
    }
    return {
        version: SCHEMA_VERSION,
        order: order,
        entries: nextEntries,
        extras: current.extras
    };
}

// targetInsertionIndex is a boundary in the pre-removal list, in the range
// 0..length. This matches an insertion marker between visible tiles.
function reorder(state, workspaceId, targetInsertionIndex) {
    const current = normalize(stateToSchema(state));
    if (!validWorkspaceId(workspaceId))
        return current;
    const wantedId = Number(workspaceId);
    const fromIndex = current.order.indexOf(wantedId);
    if (fromIndex < 0)
        return current;

    let insertion = Number(targetInsertionIndex);
    if (!Number.isInteger(insertion))
        return current;
    insertion = Math.max(0, Math.min(current.order.length, insertion));

    const nextOrder = current.order.slice();
    nextOrder.splice(fromIndex, 1);
    if (fromIndex < insertion)
        insertion -= 1;
    insertion = Math.max(0, Math.min(nextOrder.length, insertion));
    nextOrder.splice(insertion, 0, wantedId);

    const nameById = {};
    current.entries.forEach(entry => {
        nameById[entry.workspaceId] = entry.name;
    });
    return {
        version: SCHEMA_VERSION,
        order: nextOrder,
        entries: nextOrder.map(id => ({
            workspaceId: id,
            name: sanitizeName(nameById[id], id)
        })),
        extras: current.extras
    };
}

function neighbor(order, activeWorkspaceId, direction) {
    const normalized = sanitizeOrder(order);
    const active = validWorkspaceId(activeWorkspaceId)
        ? Number(activeWorkspaceId) : normalized[0];
    const currentIndex = Math.max(0, normalized.indexOf(active));
    const step = Number(direction) < 0 ? -1 : 1;
    return normalized[(currentIndex + step + normalized.length) % normalized.length];
}

function stateToSchema(state) {
    if (!state || typeof state !== "object")
        return { version: SCHEMA_VERSION, names: {}, order: [] };
    if (state.names && !state.entries) {
        const direct = Object.assign({}, collectExtras(state));
        direct.version = state.version;
        direct.names = state.names;
        direct.order = Array.isArray(state.order) ? state.order.slice() : [];
        return direct;
    }
    const names = {};
    const entries = Array.isArray(state.entries) ? state.entries : [];
    entries.forEach(entry => {
        if (!validWorkspaceId(entry?.workspaceId))
            return;
        const workspaceId = Number(entry.workspaceId);
        const name = sanitizeName(entry?.name, workspaceId);
        if (name !== defaultName(workspaceId))
            names[`${workspaceId}`] = name;
    });
    const schema = Object.assign({}, collectExtras(state));
    schema.version = SCHEMA_VERSION;
    schema.names = names;
    schema.order = Array.isArray(state.order) ? state.order.slice() : [];
    return schema;
}

function serialize(state) {
    const normalized = normalize(stateToSchema(state));
    return stateToSchema(normalized);
}

if (typeof module !== "undefined") {
    module.exports = {
        SCHEMA_VERSION: SCHEMA_VERSION,
        LEGACY_SCHEMA_VERSION: LEGACY_SCHEMA_VERSION,
        MIN_WORKSPACE_ID: MIN_WORKSPACE_ID,
        DEFAULT_WORKSPACES: DEFAULT_WORKSPACES.slice(),
        defaultName: defaultName,
        validWorkspaceId: validWorkspaceId,
        sanitizeName: sanitizeName,
        sanitizeOrder: sanitizeOrder,
        normalize: normalize,
        mergeReported: mergeReported,
        rename: rename,
        reorder: reorder,
        neighbor: neighbor,
        serialize: serialize
    };
}
