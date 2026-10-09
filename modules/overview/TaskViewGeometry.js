// Windows 11 Task View layout geometry.
//
// All sizes are expressed as fractions of the screen (or region) so the
// composition scales from FHD up to the 2560x1440 development reference and
// beyond. The numbers below reproduce the Windows 11 Task View hierarchy at
// that reference: a dominant centered window-preview area, small captions
// beneath each preview, and a bottom filmstrip of display-aspect desktop
// thumbnails with no enclosing card (see docs/TASK_VIEW_LAYOUT.md).

function clamp(value, minimum, maximum) {
    return Math.max(minimum, Math.min(maximum, value));
}

function gridForCount(count) {
    const safeCount = Math.max(1, Math.floor(count));
    const columns = Math.min(4, safeCount);
    return {
        columns: columns,
        rows: Math.ceil(safeCount / columns)
    };
}

// Width of each preview as a fraction of the window region width for a given
// window count. Windows 11 keeps previews from stretching edge-to-edge even
// with few windows: one large centered card, pairs slightly smaller than half,
// rows of four filling most of the region.
function widthCapFraction(count) {
    if (count <= 1)
        return 0.58;
    if (count === 2)
        return 0.40;
    if (count === 3)
        return 0.30;
    return 0.23;
}

// Maximum total card height (preview + caption) as a fraction of the window
// region height for a given count, so sparse layouts stay vertically centered
// like Windows 11 rather than filling the whole region.
function heightCapFraction(count) {
    if (count <= 1)
        return 0.86;
    if (count === 2)
        return 0.74;
    if (count <= 4)
        return 0.56;
    return 1.0;
}

function taskViewMetrics(width, height, displayAspect) {
    const safeWidth = Math.max(1, width);
    const safeHeight = Math.max(1, height);
    const safeAspect = Number(displayAspect) > 0.2 && Number(displayAspect) < 8
        ? Number(displayAspect) : 16 / 9;

    // Bottom filmstrip: all ten workspace thumbnails in one centered row.
    // No enclosing card; the row rests a short margin above the bottom edge,
    // matching the Windows 11 Task View desktop strip placement.
    const stripBottom = clamp(safeHeight * 0.05, 36, 96);
    const stripSpacing = clamp(safeWidth * 0.007, 12, 22);
    let thumbnailWidth = (safeWidth * 0.94 - stripSpacing * 9) / 10;
    thumbnailWidth = Math.max(120, thumbnailWidth);
    let thumbnailHeight = Math.min(thumbnailWidth / safeAspect, safeHeight * 0.18);
    if (thumbnailHeight < thumbnailWidth / safeAspect)
        thumbnailWidth = thumbnailHeight * safeAspect;
    const labelHeight = clamp(safeHeight * 0.016, 20, 26);
    const labelGap = clamp(safeHeight * 0.004, 4, 8);
    const stripHeight = labelHeight + labelGap + thumbnailHeight;

    const stripTotalWidth = thumbnailWidth * 10 + stripSpacing * 9;
    const stripViewportWidth = Math.min(stripTotalWidth, safeWidth * 0.94);
    const desktopStrip = {
        x: Math.max(0, (safeWidth - stripViewportWidth) / 2),
        y: safeHeight - stripBottom - stripHeight,
        width: stripViewportWidth,
        height: stripHeight,
        spacing: stripSpacing,
        thumbnailWidth: thumbnailWidth,
        thumbnailHeight: thumbnailHeight,
        labelHeight: labelHeight,
        labelGap: labelGap
    };

    // Main window region above the filmstrip.
    const windowX = clamp(safeWidth * 0.04, 32, 160);
    const windowY = clamp(safeHeight * 0.05, 32, 110);
    const interRegionGap = clamp(safeHeight * 0.03, 28, 56);
    const windowRegion = {
        x: windowX,
        y: windowY,
        width: safeWidth - windowX * 2,
        height: Math.max(1, desktopStrip.y - interRegionGap - windowY)
    };

    return {
        windowRegion: windowRegion,
        desktopStrip: desktopStrip
    };
}

function arrangeCards(regionWidth, regionHeight, aspects, captionHeight) {
    const safeAspects = Array.isArray(aspects) ? aspects : [];
    const count = safeAspects.length;
    if (count === 0)
        return [];

    const grid = gridForCount(count);
    const gapH = clamp(regionWidth * 0.02, 24, 64);
    const gapV = clamp(regionHeight * 0.03, 24, 56);
    const slotWidth = (regionWidth - gapH * (grid.columns - 1)) / grid.columns;
    const maxWidth = Math.min(slotWidth, regionWidth * widthCapFraction(count));
    const availableRowHeight = (regionHeight - gapV * (grid.rows - 1)) / grid.rows;
    const maxCardHeight = Math.min(availableRowHeight,
        regionHeight * heightCapFraction(count));
    const safeCaptionHeight = Math.max(0, captionHeight || 0);
    const rows = [];

    for (let rowIndex = 0; rowIndex < grid.rows; rowIndex += 1) {
        const firstIndex = rowIndex * grid.columns;
        const rowCount = Math.min(grid.columns, count - firstIndex);
        const cards = [];
        let rowWidth = 0;
        let rowHeight = 0;

        for (let columnIndex = 0; columnIndex < rowCount; columnIndex += 1) {
            const index = firstIndex + columnIndex;
            const aspect = clamp(Number(safeAspects[index]) || 16 / 9, 0.65, 2.4);
            const previewHeight = Math.max(1, Math.min(
                maxCardHeight - safeCaptionHeight,
                maxWidth / aspect
            ));
            const card = {
                index: index,
                width: previewHeight * aspect,
                height: previewHeight + safeCaptionHeight
            };
            cards.push(card);
            rowWidth += card.width;
            rowHeight = Math.max(rowHeight, card.height);
        }

        rowWidth += gapH * Math.max(0, rowCount - 1);
        rows.push({ cards: cards, width: rowWidth, height: rowHeight });
    }

    const totalHeight = rows.reduce((sum, row) => sum + row.height, 0)
        + gapV * Math.max(0, rows.length - 1);
    let rowY = (regionHeight - totalHeight) / 2;
    const arranged = new Array(count);

    rows.forEach(row => {
        let cardX = (regionWidth - row.width) / 2;
        row.cards.forEach(card => {
            arranged[card.index] = {
                x: cardX,
                y: rowY + (row.height - card.height) / 2,
                width: card.width,
                height: card.height
            };
            cardX += card.width + gapH;
        });
        rowY += row.height + gapV;
    });

    return arranged;
}

if (typeof module !== "undefined") {
    module.exports = {
        clamp: clamp,
        gridForCount: gridForCount,
        widthCapFraction: widthCapFraction,
        heightCapFraction: heightCapFraction,
        taskViewMetrics: taskViewMetrics,
        arrangeCards: arrangeCards
    };
}
