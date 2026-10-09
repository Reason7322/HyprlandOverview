// Persistent desktop presentation metadata.
//
// Hyprland workspace IDs remain the only backend identity. Names and order are
// normalized presentation data so corrupt state cannot remove or duplicate a
// workspace.

var SCHEMA_VERSION = 1;
var MIN_WORKSPACE_ID = 1;
var MAX_WORKSPACE_ID = 10;

function defaultName(workspaceId) {
    return `Desktop ${workspaceId}`;
}

function validWorkspaceId(value) {
    const number = Number(value);
    return Number.isInteger(number)
        && number >= MIN_WORKSPACE_ID
        && number <= MAX_WORKSPACE_ID;
}

function sanitizeName(value, workspaceId) {
    if (typeof value !== "string")
        return defaultName(workspaceId);
    const trimmed = value.trim();
    return trimmed.length > 0 ? trimmed : defaultName(workspaceId);
}

function sanitizeOrder(value) {
    const order = [];
    const seen = {};
    if (Array.isArray(value)) {
        value.forEach(candidate => {
            if (!validWorkspaceId(candidate))
                return;
            const workspaceId = Number(candidate);
            if (seen[workspaceId])
                return;
            seen[workspaceId] = true;
            order.push(workspaceId);
        });
    }
    for (let workspaceId = MIN_WORKSPACE_ID;
            workspaceId <= MAX_WORKSPACE_ID; workspaceId += 1) {
        if (!seen[workspaceId])
            order.push(workspaceId);
    }
    return order;
}

function normalize(raw) {
    const source = raw && typeof raw === "object"
        && raw.version === SCHEMA_VERSION ? raw : {};
    const names = source.names && typeof source.names === "object"
        && !Array.isArray(source.names) ? source.names : {};
    const order = sanitizeOrder(source.order);
    const entries = order.map(workspaceId => ({
        workspaceId: workspaceId,
        name: sanitizeName(names[`${workspaceId}`], workspaceId)
    }));
    return {
        version: SCHEMA_VERSION,
        order: order,
        entries: entries
    };
}

function rename(state, workspaceId, name) {
    const current = normalize(stateToSchema(state));
    if (!validWorkspaceId(workspaceId))
        return current;
    const wantedId = Number(workspaceId);
    const nextEntries = current.entries.map(entry => ({
        workspaceId: entry.workspaceId,
        name: entry.workspaceId === wantedId
            ? sanitizeName(name, wantedId) : entry.name
    }));
    return {
        version: SCHEMA_VERSION,
        order: current.order.slice(),
        entries: nextEntries
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
        }))
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
    if (state.names && !state.entries)
        return state;
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
    return {
        version: SCHEMA_VERSION,
        names: names,
        order: Array.isArray(state.order) ? state.order.slice() : []
    };
}

function serialize(state) {
    const normalized = normalize(stateToSchema(state));
    return stateToSchema(normalized);
}

if (typeof module !== "undefined") {
    module.exports = {
        defaultName: defaultName,
        validWorkspaceId: validWorkspaceId,
        sanitizeName: sanitizeName,
        sanitizeOrder: sanitizeOrder,
        normalize: normalize,
        rename: rename,
        reorder: reorder,
        neighbor: neighbor,
        serialize: serialize
    };
}
