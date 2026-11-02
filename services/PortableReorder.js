// Safe, configuration-independent workspace content reordering.
// Works with Hyprland 0.54's legacy dispatch and 0.55+'s Lua dispatch.
// Never reads, rewrites or reloads the user's Hyprland configuration.

function validId(id) {
    return Number.isInteger(id) && id >= 1 && id <= 2147483647;
}

function permutation(slots, identities) {
    if (!Array.isArray(slots) || !Array.isArray(identities)
            || slots.length !== identities.length || slots.length === 0)
        throw new Error("invalid desktop reorder request");
    const a = new Set(slots);
    const b = new Set(identities);
    if (a.size !== slots.length || b.size !== identities.length
            || slots.some(id => !validId(id)) || identities.some(id => !validId(id))
            || slots.some(id => !b.has(id)))
        throw new Error("reorder must contain the same unique desktop IDs");
    const mapping = {};
    slots.forEach((slot, index) => {
        if (slot !== identities[index])
            mapping[identities[index]] = slot;
    });
    return mapping;
}

function provider(systeminfo, version) {
    const match = /configProvider\s*:\s*([\w-]+)/i.exec(systeminfo);
    if (match) {
        const name = match[1].toLowerCase();
        if (name === "lua") return "lua";
        if (name === "hyprlang" || name === "legacy") return "legacy";
        throw new Error("unsupported Hyprland config provider: " + name);
    }
    // systeminfo was introduced later. Pre-Lua Hyprland supports legacy IPC.
    const versionMatch = /(?:^|["\s])(?:v)?0\.(\d+)\./i.exec(version);
    if (versionMatch && Number(versionMatch[1]) < 55)
        return "legacy";
    throw new Error("cannot identify Hyprland IPC syntax; no windows were moved");
}

function plan(slotOrder, identityOrder, clients, workspaces, rules) {
    const mapping = permutation(slotOrder, identityOrder);
    const sources = Object.keys(mapping).map(Number);
    if (sources.length === 0)
        return {mapping, rows: [], moves: [], recovery: []};
    if (!Array.isArray(clients) || !Array.isArray(workspaces) || !Array.isArray(rules))
        throw new Error("could not inspect live Hyprland state");
    const affected = new Set([...sources, ...Object.values(mapping)]);
    // Binding windows to workspace IDs means renumbering would conflict with
    // the user's rules. Never modify or attempt to outsmart such rules.
    for (const rule of rules) {
        const selector = String(rule.workspaceString ?? rule.workspaceId
            ?? rule.workspaceName ?? "");
        // Style-only rules (for example w[tv1] with border=false) cannot
        // dictate workspace identity or monitor placement. Reject only rules
        // that pin workspace identity/placement into the affected permutation.
        const placesWorkspace = (rule.monitor !== undefined && rule.monitor !== null
                && rule.monitor !== "") || !!rule.persistent || !!rule.isPersistent;
        if (!placesWorkspace) continue;
        if (selector.startsWith("special:")) continue;
        if (/^\d+$/.test(selector) && !affected.has(Number(selector))) continue;
        throw new Error("workspace rule may pin an affected desktop; reorder refused");
    }
    const affectedMonitors = new Set(workspaces.filter(w => affected.has(w.id)
        && typeof w.monitor === "string" && w.monitor).map(w => w.monitor));
    if (affectedMonitors.size > 1)
        throw new Error("cross-monitor desktop reordering is not yet supported");

    const rows = [];
    for (const client of clients) {
        const source = client?.workspace?.id;
        if (!Object.prototype.hasOwnProperty.call(mapping, source)) continue;
        const address = String(client.address ?? "");
        if (!/^0x[0-9a-f]+$/i.test(address))
            throw new Error("client has no safe window address");
        if ((client.grouped?.length ?? 0) > 0 || client.pinned
                || client.swallowing && client.swallowing !== "0x0"
                || client.fullscreen !== 0 || client.fullscreenClient > 0
                || client.pseudo)
            throw new Error("grouped, pinned, swallowed, fullscreen or pseudo windows cannot be safely reordered");
        rows.push({address, source, destination: mapping[source]});
    }

    // Dispatches target windows by exact address, so a permutation needs no
    // staging workspaces. Do not touch unapproved/unrelated workspace IDs.
    return {
        mapping, rows,
        moves: rows.map(r => ({address:r.address, target:r.destination})),
        recovery: rows.map(r => ({address:r.address, target:r.source}))
    };
}

function dispatch(move, mode) {
    if (!/^0x[0-9a-f]+$/i.test(move.address) || !validId(move.target))
        throw new Error("unsafe dispatch request");
    if (mode === "lua")
        return "hyprctl eval 'hl.dispatch(hl.dsp.window.move({workspace = \""
            + move.target + "\", follow = false, window = \"address:"
            + move.address + "\"}))'";
    if (mode === "legacy")
        return "hyprctl dispatch movetoworkspacesilent '"
            + move.target + ",address:" + move.address + "'";
    throw new Error("unsupported Hyprland dispatch mode");
}

function batch(moves, mode) {
    return "set -e\n" + moves.map(move => dispatch(move, mode)
        + ' | grep -qx ok').join("\n") + "\n";
}

function checkClients(snapshot, rows, phase) {
    if (!Array.isArray(snapshot)) return false;
    const byAddress = {};
    snapshot.forEach(c => { byAddress[c.address] = c.workspace?.id; });
    for (const row of rows) {
        const expected = phase === "second" ? row.destination : row.source;
        if (byAddress[row.address] !== expected)
            return false;
    }
    return true;
}

if (typeof module !== "undefined") module.exports = {
    validId, permutation, provider, plan, dispatch, batch, checkClients
};
