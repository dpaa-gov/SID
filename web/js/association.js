// Association tab: is a known stature consistent with a bone's measurements?

import {
    $, postJSON, showError, progress, makeSelect, makeChoice, boneName, setChoices, valueOf, valuesOf,
    renderMeasurements, entered, initSettings, initCopy, markRun, statTile, drawRegression, fixed, unitShort,
} from "./common.js";
import { fillTable, cellText } from "./table.js";

// The places each number is rounded to, as the R SID rounded them
const PLACES = { PI: 2, Value: 2, "Point estimate": 2, Lower: 2, Upper: 2, Slope: 3, Intercept: 3, "R²": 3, p: 3 };

export function initAssociation(reference) {
    const meta = reference.meta;
    const labels = () => valuesOf(selects.reference);
    let lastTable = [];

    const selects = {
        reference: makeSelect("a-reference", () => referenceChanged()),
        element: makeSelect("a-element", () => elementChanged(), boneName),
        side: makeChoice("a-side"),
    };
    // the unit is chosen beside the known stature, not in the settings
    const form = initSettings("a-");

    function elementChanged() {
        renderMeasurements($("a-values"), reference.measurements(labels(), valueOf(selects.element)), reference);
    }

    function referenceChanged() {
        setChoices(selects.element, reference.elements(labels()));
        elementChanged();
    }

    function renderResult(result, body) {
        markRun($("a-results"));
        const { columns, rows } = result.results;
        const row = rows[0];
        const cell = (name) => row[columns.indexOf(name)];
        const unit = unitShort(body.unit);
        const interval = `${Math.round(body.interval * 100)}%`;
        $("a-summary").replaceChildren(
            statTile(["p-value", fixed(cell("p"), 3)]),
            statTile(["Expected measurement", fixed(cell("Point estimate"), 2), "mm"]),
            statTile([`${interval} prediction interval`, `${fixed(cell("Lower"), 2)} – ${fixed(cell("Upper"), 2)}`, "mm"]),
            statTile(["Reference sample", cell("n")]));
        fillTable($("a-table"), result.results, PLACES);
        lastTable = [columns, ...rows.map((r) => r.map((value, c) => cellText(columns[c], value, PLACES)))];
        drawRegression("a-plot", result.plot, { x: cell("Known stature"), y: cell("Value") },
            { x: `Stature (${unit})`, y: "Summed measurements (mm)" });
    }

    initCopy($("a-copy"), () => lastTable);

    // Ready for the next specimen: the typed measurements, the known stature and
    // the result go; the reference groups, the element, the side and the settings stay.
    $("a-clear").addEventListener("click", () => {
        const fields = [$("a-known"), ...$("a-values").querySelectorAll("input")];
        for (const field of fields) field.value = "";
        $("a-results").hidden = true;
        $("a-known").focus();
    });

    $("a-form").addEventListener("submit", async (event) => {
        event.preventDefault();
        const known = $("a-known").value;
        const body = { references: labels(), element: valueOf(selects.element), side: selects.side.getValue(),
            ...form.settings(), known_stature: known === "" ? null : Number(known), values: entered($("a-values")) };
        progress.show("Running association...");
        progress.set(50, "Running association...");
        try {
            renderResult(await postJSON("api/associate", body), body);
        } catch (error) {
            showError(error.message);
        } finally {
            progress.hide();
        }
    });

    setChoices(selects.reference, reference.labels(), meta.default_references);
    referenceChanged();
}
