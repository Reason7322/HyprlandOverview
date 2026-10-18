// Automatic, presentation-only workspace labels.
//
// A visible desktop holds windows of exactly one distinct application when all
// attributable windows share one WM class (any number of such windows still
// counts as that single application). In that case the view may temporarily
// show the application's friendly name instead of the saved workspace name.
// Zero windows, several different applications, or a non-ordinary workspace ID
// always fall back to the saved name, with "Desktop N" when no usable saved
// name exists.
//
// The resolver is pure: it reads its input object and returns a plain result.
// It never persists anything, so a dynamic label can only ever live in the QML
// view. Manual renames always operate on the saved name passed as savedName.

// Product names that mechanical class cleanup cannot reconstruct well enough
// for this system's common applications. Lookup is case-insensitive; anything
// not listed here falls back to the cleaned-up last class segment below.
var FRIENDLY_NAMES = {
    "org.mozilla.firefox": "Firefox",
    "com.brave.browser": "Brave",
    // Steam dialogs report their own WM class but belong to the launcher UI.
    "steamwebhelper": "Steam",
    "ai.elementlabs.lmstudio": "LM Studio",
    // KDE Connect reports a generic class whose last segment is just "app".
    "org.kde.kdeconnect.app": "KDE Connect",
    "qmmp": "QMMP"
};

function defaultLabel(workspaceId) {
    return `Desktop ${workspaceId}`;
}

// Windows without a usable class are skipped, not treated as an unknown app:
// attribution needs a stable identifier and the window title is deliberately
// never used for application identity.
function appClass(window) {
    const value = window?.class ?? window?.classname ?? "";
    return `${value}`.trim();
}

// Case-insensitive deduplication keeps first-seen casing for display while
// counting repeated windows of the same application only once.
function distinctApps(windows) {
    const apps = [];
    const seen = {};
    if (!Array.isArray(windows))
        return apps;
    windows.forEach(win => {
        const cls = appClass(win);
        if (cls.length === 0)
            return;
        const key = cls.toLowerCase();
        if (seen[key])
            return;
        seen[key] = true;
        apps.push({ key: key, class: cls });
    });
    return apps;
}

// Presentation-friendly label for a WM class: built-in product name first, then
// the last dotted segment split on dashes/underscores. All-caps tokens stay as
// acronyms; anything else is capitalized with lowercase remainder so raw
// identifiers never reach the visible label unchanged when cleanup succeeds.
function friendlyName(cls) {
    const value = `${cls ?? ""}`.trim();
    if (value.length === 0)
        return "";
    const known = FRIENDLY_NAMES[value.toLowerCase()];
    if (known && `${known}`.trim().length > 0)
        return `${known}`.trim();

    const segments = value.split(".");
    let segment = "";
    for (let index = segments.length - 1; index >= 0; index -= 1) {
        if (segments[index].trim().length > 0) {
            segment = segments[index];
            break;
        }
    }
    const tokens = segment.split(/[-_]+/).filter(token => token.length > 0);
    if (tokens.length === 0)
        return value;
    return tokens.map(token => /^[A-Z][A-Z0-9]*$/.test(token)
        ? token
        : `${token.charAt(0).toUpperCase()}${token.slice(1).toLowerCase()}`).join(" ");
}

// workspaceId must be an ordinary positive integer desktop ID; any other
// identifier (named/space, zero, negative, missing) is never eligible for a
// dynamic label.
function resolve(input) {
    const source = input && typeof input === "object" ? input : {};
    const savedRaw = `${source.savedName ?? ""}`.trim();
    const workspaceId = Number(source.workspaceId);
    const ordinary = Number.isInteger(workspaceId) && workspaceId >= 1;
    const savedLabel = savedRaw.length > 0 ? savedRaw : defaultLabel(workspaceId);

    if (!ordinary)
        return { label: savedLabel, source: "saved", applicationClass: null };

    const apps = distinctApps(source.windows);
    if (apps.length === 1) {
        const name = friendlyName(apps[0].class);
        if (name.length > 0)
            return {
                label: name,
                source: "dynamic",
                applicationClass: apps[0].class
            };
    }
    return { label: savedLabel, source: "saved", applicationClass: null };
}

function windowsForWorkspace(windowList, workspaceId) {
    const id = Number(workspaceId);
    if (!Number.isInteger(id) || id < 1)
        return [];
    if (!Array.isArray(windowList))
        return [];
    return windowList.filter(win => win?.workspace?.id === id
        && `${win?.address ?? ""}`.length > 0);
}

if (typeof module !== "undefined") {
    module.exports = {
        FRIENDLY_NAMES: Object.assign({}, FRIENDLY_NAMES),
        defaultLabel: defaultLabel,
        appClass: appClass,
        distinctApps: distinctApps,
        friendlyName: friendlyName,
        resolve: resolve,
        windowsForWorkspace: windowsForWorkspace
    };
}
