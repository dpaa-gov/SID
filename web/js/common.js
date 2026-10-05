// Shared pieces: API calls, dropdowns, the reference-data model, measurement
// fields, settings, dialogs and plots. Every URL is relative so the app works
// under whatever path Atlas serves it.

export const $ = (id) => document.getElementById(id);

async function request(path, options) {
    let response;
    try {
        response = await fetch(path, options);
    } catch {
        throw new Error("The server could not be reached");
    }
    const body = await response.json().catch(() => ({}));
    if (!response.ok) {
        const error = new Error(body.error || `The server returned an error (${response.status})`);
        error.status = response.status;
        throw error;
    }
    return body;
}

export const getJSON = (path) => request(path);
export const postJSON = (path, body) =>
    request(path, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) });

export const capFirst = (text) => text.charAt(0).toUpperCase() + text.slice(1);

// How bones are shown: "Humerus". The lower-case name from ARDS stays the value that is sent.
export const boneName = (value) => ({ text: capFirst(value) });

// --- Dialogs ---

export function showError(message) {
    $("error-text").textContent = message;
    bootstrap.Modal.getOrCreateInstance($("error-modal")).show();
}

export const progress = {
    show(text = "Starting...") {
        this.set(0, text);
        bootstrap.Modal.getOrCreateInstance($("progress-modal")).show();
    },
    set(percent, text) {
        $("progress-bar").style.width = percent + "%";
        $("progress-text").textContent = text;
    },
    hide() {
        bootstrap.Modal.getOrCreateInstance($("progress-modal")).hide();
    },
};

// --- Tooltips inside things that scroll ---

// A tooltip drawn inside a scrolling list is cut off at the list's edge. For
// the scrolling measurement fields and an open dropdown list, one tooltip that
// floats over the page is placed by script from where the hovered thing is on
// screen: above a field's code, beside a name in a list. It goes when the
// pointer leaves or anything scrolls.
const floatingTip = document.createElement("div");
floatingTip.className = "floating-tip";
floatingTip.hidden = true;
document.body.append(floatingTip);
document.addEventListener("mouseover", (event) => {
    const target = event.target.closest?.(".measure-scroll [data-tooltip], .ts-dropdown .option[data-tooltip]");
    floatingTip.hidden = !target;
    if (!target) return;
    floatingTip.textContent = target.dataset.tooltip;
    // Where the hovered thing is comes in screen pixels; the tooltip is placed
    // in the page's own, which differ by the page's zoom (fitToScreen)
    const zoom = zoomFor();
    const r = target.getBoundingClientRect();
    const at = { left: r.left / zoom, right: r.right / zoom, top: r.top / zoom, height: r.height / zoom };
    const beside = target.matches(".option");
    floatingTip.style.left = `${beside ? at.right + 8 : at.left}px`;
    floatingTip.style.top = `${beside ? at.top + (at.height - floatingTip.offsetHeight) / 2 : at.top - floatingTip.offsetHeight - 6}px`;
});
document.addEventListener("scroll", () => { floatingTip.hidden = true; }, true);

// --- Dropdowns (Tom Select) ---

// `describe(value)` may return { text, tooltip } to show a choice differently
// from the value that is sent to the server.
export function makeSelect(id, onChange, describe) {
    const element = $(id);
    const chip = (data, escape) =>
        `<div${data.tooltip ? ` data-tooltip="${escape(data.tooltip)}"` : ""}>${escape(data.text)}</div>`;
    const select = new TomSelect(element, {
        // each tag in a tag list carries a small × that takes it out
        plugins: element.multiple ? { remove_button: { title: "Remove" } } : {},
        render: { item: chip, option: chip },
        maxOptions: null,
        hidePlaceholder: true,
        hideSelected: element.multiple,
        closeAfterSelect: !element.multiple,
        // a dropdown is done once a value is picked; leaving it focused keeps its search field open
        onItemAdd() { if (!element.multiple) this.blur(); },
        onChange: () => onChange && onChange(),
    });
    select.describe = describe;
    return select;
}

// A choice between a few fixed options, as a row of buttons: a side, the
// interval, the unit. Read like a dropdown (`getValue`), so the forms treat
// the two alike.
export function makeChoice(name) {
    const inputs = [...document.querySelectorAll(`input[name="${name}"]`)];
    return { getValue: () => inputs.find((input) => input.checked).value };
}

// Replaces the choices. A dropdown keeps its value where still valid;
// otherwise selects `fallback` (the first value for a dropdown).
export function setChoices(select, values, fallback) {
    const multiple = select.input.multiple;
    const chosen = [].concat(select.getValue()).filter(Boolean);
    const current = chosen.filter((value) => values.includes(value));
    select.clear(true);
    select.clearOptions();
    select.addOptions(values.map((value) => ({ value, text: value, ...(select.describe ? select.describe(value) : {}) })));
    let selected = fallback !== undefined ? fallback : multiple ? values : values.slice(0, 1);
    if (fallback === undefined && current.length) selected = current;
    select.setValue(multiple ? selected : selected[0] ?? "", true);
    select.refreshOptions(false);
}

export const valueOf = (select) => select.getValue();
export const valuesOf = (select) => [].concat(select.getValue()).filter(Boolean);

// --- Reference data: what the selected groups can support ---

export class Reference {
    constructor(meta) {
        this.meta = meta;
        this.groups = new Map(meta.groups.map((group) => [
            group.label,
            new Map(group.elements.map((e) => [e.element, new Set(e.measurements)])),
        ]));
        // every measurement is a length in millimetres; the tooltip is where that is said
        this.name = new Map(meta.measurements.map((m) => [m.code, m.name ? `${m.name} (mm)` : m.name]));
        this.codes = new Map();
        for (const m of meta.measurements) {
            if (!this.codes.has(m.bone)) this.codes.set(m.bone, []);
            this.codes.get(m.bone).push(m.code);
        }
    }

    labels() {
        return this.meta.groups.map((group) => group.label);
    }

    // Elements present in any selected group
    elements(labels) {
        return this.meta.bones.filter((bone) => labels.some((label) => this.groups.get(label)?.has(bone)));
    }

    // Measurements of an element with data in any selected group
    measurements(labels, bone) {
        return (this.codes.get(bone) || []).filter((code) =>
            labels.some((label) => this.groups.get(label)?.get(bone)?.has(code)));
    }

    // The measurements stature is estimated from, bone by bone, with data in any selected group
    estimationMeasurements(labels) {
        return this.meta.measurements.filter((m) => m.stature && this.measurements(labels, m.bone).includes(m.code))
            .map((m) => m.code);
    }
}

// --- Measurement fields ---

// One row per measurement: its code, with its full name on hover, beside its
// field. What was already typed in a field stays when the list is redrawn.
export function renderMeasurements(container, codes, reference) {
    const prefix = container.id;
    const typed = new Map([...container.querySelectorAll("input")].map((input) => [input.dataset.code, input.value]));
    container.replaceChildren();
    for (const code of codes) {
        const label = document.createElement("label");
        const text = document.createElement("span");
        text.textContent = capFirst(code);
        if (reference.name.get(code)) text.dataset.tooltip = reference.name.get(code);
        label.htmlFor = `${prefix}-${code}`;
        label.append(text);
        const input = document.createElement("input");
        input.type = "number";
        input.className = "form-control";
        input.id = `${prefix}-${code}`;
        input.dataset.code = code;
        input.min = 0;
        input.max = 999;
        input.step = "any";
        input.value = typed.get(code) ?? "";
        container.append(label, input);
    }
}

// The values typed in, by code; blank fields are sent as null
export const entered = (container) => Object.fromEntries(
    [...container.querySelectorAll("input")].map((input) => [input.dataset.code, input.value === "" ? null : Number(input.value)]));

// --- Settings (ids prefixed "e-" or "a-") ---

export function initSettings(prefix) {
    const form = $(prefix + "form");
    const checked = (name) => form.querySelector(`input[name="${prefix}${name}"]:checked`).value;
    const bootstrapSwitch = $(prefix + "bootstrap");
    const settings = () => ({
        interval: Number(checked("interval")),
        unit: checked("unit"),
        ...(bootstrapSwitch ? { bootstrap: bootstrapSwitch.checked } : {}),
    });
    return { settings };
}

export const unitShort = (unit) => (unit === "Inches" ? "in" : "cm");

// Puts rows of text on the clipboard, tab-separated, which pastes into a
// spreadsheet as cells and into a document as a table. Returns whether it worked.
export async function copyRows(rows) {
    const text = rows.map((row) => row.map((cell) => String(cell ?? "").trim()).join("\t")).join("\n");
    try {
        await navigator.clipboard.writeText(text);
        return true;
    } catch {
        // no clipboard access (an embedded frame, or plain http): copy from a hidden text box
        const box = document.createElement("textarea");
        box.value = text;
        box.style.position = "fixed";
        box.style.opacity = "0";
        document.body.append(box);
        box.select();
        const copied = document.execCommand("copy");
        box.remove();
        return copied;
    }
}

export function initCopy(button, rows) {
    button.addEventListener("click", async () => {
        const label = button.querySelector("span");
        label.textContent = (await copyRows(rows())) ? "Copied" : "Copy failed";
        setTimeout(() => { label.textContent = "Copy"; }, 1500);
    });
}

// Shows a results panel and counts the analyses it has displayed, so the
// browser test can tell a new result from the last one
export function markRun(panel) {
    panel.hidden = false;
    panel.dataset.run = Number(panel.dataset.run || 0) + 1;
}

// --- Plots ---

// The toolbar's camera asks what size to save at. Plotly's own saves at the
// size on screen, which is rarely the size a figure is wanted at. The dialog
// starts at the size on screen and then keeps what was last asked for.
let imagePlot = null;
let imageSizeChosen = false;
function askImageSize(plot) {
    imagePlot = plot;
    if (!imageSizeChosen) {
        $("image-width").value = plot.offsetWidth;
        $("image-height").value = plot.offsetHeight;
    }
    bootstrap.Modal.getOrCreateInstance($("image-modal")).show();
}
$("image-form").addEventListener("submit", (event) => {
    event.preventDefault();
    imageSizeChosen = true;
    Plotly.downloadImage(imagePlot, {
        format: $("image-format").value, width: Number($("image-width").value), height: Number($("image-height").value),
        filename: imagePlot.dataset.filename,
    });
    bootstrap.Modal.getOrCreateInstance($("image-modal")).hide();
});

// The labels written on a plot ("Specimen") can be taken off, for a figure
// that is captioned elsewhere. The choice holds for later plots too, until
// the button is pressed again.
let labelsHidden = false;
function toggleLabels() {
    labelsHidden = !labelsHidden;
    // on every plot drawn, not only the one whose button was pressed, so none is out of step with the choice
    for (const plot of document.querySelectorAll(".js-plotly-plot")) {
        const labels = plot.layout.annotations ?? [];
        if (labels.length) Plotly.relayout(plot, Object.fromEntries(labels.map((_, i) => [`annotations[${i}].visible`, !labelsHidden])));
    }
}
const LABEL_ICON = { width: 24, height: 24,
    path: "M17.63 5.84C17.27 5.33 16.67 5 16 5L5 5.01C3.9 5.01 3 5.9 3 7v10c0 1.1.9 1.99 2 1.99L16 19c.67 0 1.27-.33 1.63-.84L22 12l-4.37-6.16z" };

export const PLOT_CONFIG = {
    displaylogo: false,
    responsive: true,
    // the only two buttons on the toolbar
    modeBarButtons: [[
        { name: "toggleLabels", title: "Hide or show labels", icon: LABEL_ICON, click: toggleLabels },
        { name: "saveImage", title: "Save plot as an image", icon: Plotly.Icons.camera, click: askImageSize },
    ]],
};
// Shared by every plot. Toolbar colours are set explicitly so they do not
// depend on the theme's link colour. Plots stay as drawn: there is no button
// to undo a zoom, so dragging on the plot or along an axis does nothing.
export const PLOT_LAYOUT = {
    dragmode: false,
    hovermode: false, // the app's own hover labels instead (plotHover)
    template: { layout: { xaxis: { fixedrange: true }, yaxis: { fixedrange: true } } },
    plot_bgcolor: "#ffffff",
    paper_bgcolor: "#ffffff",
    modebar: { color: "rgba(68, 68, 68, 0.35)", activecolor: "#d4a843", bgcolor: "rgba(255, 255, 255, 0)" },
    showlegend: false,
};
export const COLORS = { gold: "#d4a843" };

// The reference sample, the fitted line, its prediction interval, and the
// specimen in gold, labelled on the side away from the nearer edge
// Every tick label is shown ("allow"): Plotly hides those it measures as
// spilling past the plot, and on a zoomed page (fitToScreen) it measures them
// too large and hides the last on each axis. Margins leave room only for the
// axis labels; the plot's size comes from
// its box (css/sid.css), which keeps one shape at any screen width.
const PLOT_MARGIN = { t: 12, r: 12, b: 50, l: 64 };

// A screen wider than 1920px shows the page larger, by three quarters of the
// width it has beyond 1920: 1.25 times at 2560, 1.75 at 3840. Scaled to fill
// the screen it looked too large. (A screen the system already scales, such
// as 4K at 200%, reports its scaled width and is left alone.)
const DESIGN_WIDTH = 1920;
const ZOOM_SHARE = 0.75;
const zoomFor = () => 1 + ZOOM_SHARE * Math.max(0, window.innerWidth / DESIGN_WIDTH - 1);
export function fitToScreen() {
    const apply = () => {
        document.body.style.zoom = zoomFor() === 1 ? "" : String(zoomFor());
    };
    window.addEventListener("resize", apply);
    apply();
}

// --- Hover labels ---

// Plots show their own hover labels, not Plotly's: one look, in the app's
// tooltip style, at any size. Plotly's would also name the wrong point on a
// zoomed page (fitToScreen), as it places the pointer without allowing for the
// zoom; these do. A label names the point nearest the pointer, or the bar under
// it; fitted lines and intervals have none. Where the points are is worked out
// from Plotly's axes, so nothing is measured on screen.
const plotTip = document.createElement("div");
plotTip.className = "plot-tip";
plotTip.hidden = true;
document.body.append(plotTip);
document.addEventListener("scroll", () => { plotTip.hidden = true; }, true);

const NEAR = 20; // how close to a point the pointer must be, in page pixels
const hoverNumber = (value) => String(Math.round(value * 1e4) / 1e4);

// What is under the pointer at (mx, my), in the plot's own pixels: the text
// for the label and where it points, or null
function hoveredAt(gd, mx, my) {
    const fl = gd._fullLayout, xa = fl.xaxis, ya = fl.yaxis;
    const px = (x) => xa._offset + xa.d2p(x), py = (y) => ya._offset + ya.d2p(y);
    // the titles the plot was given; Plotly fills in a placeholder where there is none
    const xTitle = gd.layout.xaxis?.title?.text, yTitle = gd.layout.yaxis?.title?.text;
    let best = null;
    for (const trace of gd.calcdata) {
        const full = trace[0].trace;
        if (full.visible !== true) continue;
        if (full.type === "bar" || full.type === "histogram") {
            for (const bin of trace) {
                const lower = bin.ph0 ?? bin.p - full.width / 2, upper = bin.ph1 ?? bin.p + full.width / 2;
                const base = bin.b || 0, top = base + bin.s;
                if (!bin.s || mx < px(lower) || mx > px(upper) || my < py(top) || my > py(base)) continue;
                const range = full.type === "histogram" ? `${hoverNumber(lower)} – ${hoverNumber(upper)}` : hoverNumber(bin.p);
                return { x: px(bin.p), y: py(top), text: `${full.name}\n${xTitle || "Range"}: ${range}\nCount: ${bin.s}` };
            }
            continue;
        }
        if (!full.mode?.includes("markers")) continue; // a fitted line or an interval
        full.x.forEach((x, i) => {
            const y = full.y[i];
            const distance = Math.hypot(px(x) - mx, py(y) - my);
            if (distance <= NEAR && (!best || distance < best.distance)) {
                best = { distance, x: px(x), y: py(y), text: `${full.name}\n${xTitle || "x"}: ${hoverNumber(x)}\n${yTitle || "y"}: ${hoverNumber(y)}` };
            }
        });
    }
    return best;
}

function showHover(gd, event) {
    const zoom = zoomFor();
    if (!gd._fullLayout) {
        plotTip.hidden = true;
        return;
    }
    const r = gd.getBoundingClientRect();
    const hit = hoveredAt(gd, (event.clientX - r.left) / zoom, (event.clientY - r.top) / zoom);
    plotTip.hidden = !hit;
    if (!hit) return;
    plotTip.textContent = hit.text;
    // beside the point, on the side with room for it
    const left = r.left / zoom + hit.x, top = r.top / zoom + hit.y - plotTip.offsetHeight / 2;
    const onLeft = hit.x + 12 + plotTip.offsetWidth > gd._fullLayout.width;
    plotTip.style.left = `${onLeft ? left - 12 - plotTip.offsetWidth : left + 12}px`;
    plotTip.style.top = `${top}px`;
}

// Gives a plot these hover labels; once is enough for a plot that is redrawn
export function plotHover(id) {
    const gd = $(id);
    if (gd.dataset.plotHover) return;
    gd.dataset.plotHover = "on";
    let frame = 0, last = null;
    gd.addEventListener("mousemove", (event) => {
        last = event;
        frame ||= requestAnimationFrame(() => { frame = 0; showHover(gd, last); });
    });
    gd.addEventListener("mouseleave", () => { plotTip.hidden = true; });
}

export function drawRegression(id, plot, specimen, axes) {
    plotHover(id);
    const line = (y, name, color, dash = "dash") => ({ x: plot.x, y, name, type: "scatter", mode: "lines", line: { color, dash } });
    const onLeft = specimen.x - Math.min(specimen.x, ...plot.x) > Math.max(specimen.x, ...plot.x) - specimen.x;
    Plotly.react(id, [
        { x: plot.x, y: plot.y, name: "Reference", type: "scatter", mode: "markers", marker: { color: "grey", size: 6 } },
        line(plot.fit, "OLS", COLORS.gold, "solid"),
        line(plot.lower, "Lower PI", "black"),
        line(plot.upper, "Upper PI", "black"),
        { x: [specimen.x], y: [specimen.y], name: "Specimen", type: "scatter", mode: "markers",
          marker: { color: COLORS.gold, size: 12 } },
    ], { ...PLOT_LAYOUT, margin: PLOT_MARGIN, xaxis: { title: { text: axes.x }, ticklabeloverflow: "allow" },
        yaxis: { title: { text: axes.y }, ticklabeloverflow: "allow" },
        annotations: [{ x: specimen.x, y: specimen.y, text: "Specimen", showarrow: false, xanchor: onLeft ? "right" : "left",
            xshift: onLeft ? -10 : 10, yanchor: "middle", font: { size: 12, color: "#2a4051" }, visible: !labelsHidden }] }, PLOT_CONFIG);
}

// --- Stat tiles ---

// One headline figure: the value large, an optional note beside it, its label underneath
export function statTile([label, value, note]) {
    const element = document.createElement("div");
    element.className = "stat-tile";
    const number = document.createElement("div");
    number.className = "stat-value";
    // thousands separators on whole numbers; anything else exactly as given
    number.textContent = Number.isInteger(value) ? value.toLocaleString("en-US") : String(value);
    if (note) {
        const small = document.createElement("span");
        small.className = "stat-note";
        small.textContent = note;
        number.append(small);
    }
    const name = document.createElement("div");
    name.className = "stat-label";
    name.textContent = label;
    element.append(number, name);
    return element;
}

// Numbers shown with the places they were rounded to, so 64 reads 64.00
export const fixed = (value, places) => (value === null ? "" : Number(value).toFixed(places));

// --- Tables ---

// Columns of numbers are set against the right edge, so their digits line up
export const NUMERIC_COLUMNS = new Set(["PI", "Value", "Point estimate", "Lower", "Upper", "n", "Slope", "Intercept",
    "R²", "Known stature", "p"]);
