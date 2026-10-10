// Window-card selection follows the visual order supplied by WindowOverview.
// Addresses remain the stable identity so model refreshes do not accidentally
// activate or close a different card at the same index.

function addresses(values) {
    const result = [];
    const seen = {};
    if (!Array.isArray(values))
        return result;
    values.forEach(value => {
        const address = typeof value === "string" ? value.trim() : "";
        if (address.length === 0 || seen[address])
            return;
        seen[address] = true;
        result.push(address);
    });
    return result;
}

function reconcile(values, selectedAddress) {
    const ordered = addresses(values);
    if (ordered.length === 0)
        return "";
    const selected = `${selectedAddress ?? ""}`;
    return ordered.includes(selected) ? selected : ordered[0];
}

function exact(values, requestedAddress) {
    const requested = typeof requestedAddress === "string"
        ? requestedAddress.trim()
        : "";
    return addresses(values).includes(requested) ? requested : "";
}

function move(values, selectedAddress, direction) {
    const ordered = addresses(values);
    if (ordered.length === 0)
        return "";
    const selected = reconcile(ordered, selectedAddress);
    const index = Math.max(0, ordered.indexOf(selected));
    const step = Number(direction) < 0 ? -1 : 1;
    return ordered[(index + step + ordered.length) % ordered.length];
}

if (typeof module !== "undefined") {
    module.exports = {
        addresses: addresses,
        exact: exact,
        reconcile: reconcile,
        move: move
    };
}
