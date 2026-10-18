// Wheel-event policy for the horizontal workspace strip.
//
// Some physical mouse wheels arrive through Qt as TouchPad devices. Discrete
// wheel events still carry angle deltas without pixel deltas, while smooth
// touchpad gestures carry pixel deltas and should remain owned by Flickable.

function finiteNumber(value, fallback) {
    const number = Number(value);
    return Number.isFinite(number) ? number : fallback;
}

function action(input) {
    const source = input && typeof input === "object" ? input : {};
    const contentX = finiteNumber(source.contentX, 0);
    const angleDeltaY = finiteNumber(source.angleDeltaY, 0);
    const pixelDeltaX = finiteNumber(source.pixelDeltaX, 0);
    const pixelDeltaY = finiteNumber(source.pixelDeltaY, 0);

    // Smooth touchpad gestures belong to Flickable. Marking the event
    // unaccepted lets its normal horizontal gesture handling continue.
    if (pixelDeltaX !== 0 || pixelDeltaY !== 0)
        return { accepted: false, contentX: contentX };

    if (source.reorderActive)
        return { accepted: true, contentX: contentX };

    // No usable discrete wheel delta: release the event to other handlers.
    if (angleDeltaY === 0)
        return { accepted: false, contentX: contentX };

    const contentWidth = finiteNumber(source.contentWidth, 0);
    const viewportWidth = finiteNumber(source.viewportWidth, 0);
    const maxScrollX = Math.max(0, contentWidth - viewportWidth);
    const step = Math.max(0, finiteNumber(source.step, 0));
    if (maxScrollX <= 0 || step <= 0)
        return { accepted: true, contentX: contentX };

    const dx = angleDeltaY > 0 ? -step : step;
    return {
        accepted: true,
        contentX: Math.max(0, Math.min(maxScrollX, contentX + dx))
    };
}

if (typeof module !== "undefined") {
    module.exports = {
        action: action
    };
}
