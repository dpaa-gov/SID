// Estimation tab: stature estimated from typed-in measurements, one model for
// each combination of them. The model with the narrowest interval is shown
// first; choosing another row in the table shows that one.

import {
    $, postJSON, showError, progress, makeSelect, setChoices, valuesOf, renderMeasurements, entered, numberFields,
    sidesOf, initSharedSide, initSettings, initCopy, markRun, statTile, drawRegression, fixed, unitShort,
} from "./common.js";
import { ModelTable } from "./table.js";

// The places each number is rounded to, as the R SID rounded them
const PLACES = { PI: 2, Value: 2, "Point estimate": 2, Lower: 2, Upper: 2, Slope: 5, Intercept: 2, "R²": 3 };

export function initEstimation(reference) {
    const meta = reference.meta;
    const labels = () => valuesOf(selects.reference);
    let request = null; // what the results on screen were made from

    const selects = {
        reference: makeSelect("e-reference", () => referenceChanged()),
    };
    const form = initSettings("e-");
    const table = new ModelTable($("e-table"), PLACES, (i) => showModel(i));

    // Each measurement has its own side. The Side buttons over the list set
    // them all, and show the one side they share, or neither when they differ.
    const sides = initSharedSide("e-side", $("e-values"));

    function referenceChanged() {
        renderMeasurements($("e-values"), reference.estimationMeasurements(labels()), reference, { sides: true, side: sides.value() });
        sides.show();
    }

    const column = (name) => request.results.columns.indexOf(name);
    const cell = (i, name) => request.results.rows[i][column(name)];

    // The summary tiles and plot for one model
    function draw(i, plot) {
        const unit = unitShort(request.body.unit);
        const interval = `${Math.round(request.body.interval * 100)}%`;
        $("e-summary").replaceChildren(
            statTile(["Stature estimate", fixed(cell(i, "Point estimate"), 2), unit]),
            statTile([`${interval} prediction interval`, `${fixed(cell(i, "Lower"), 2)} – ${fixed(cell(i, "Upper"), 2)}`, unit]),
            statTile(["Reference sample", cell(i, "n"), cell(i, "Method")]),
            statTile(["Measurements", cell(i, "Measurements")]));
        $("e-summary").lastChild.querySelector(".stat-value").classList.add("stat-text");
        drawRegression("e-plot", plot, { x: cell(i, "Value"), y: cell(i, "Point estimate") },
            { x: "Summed measurements (mm)", y: `Stature (${unit})` });
    }

    async function showModel(i) {
        const shown = request;
        try {
            // the codes, without the (L) or (R) after each when the sides differ
            const measurements = cell(i, "Measurements").toLowerCase().split(" ").filter((word) => !word.startsWith("("));
            const { plot } = await postJSON("api/estimate/plot", { ...shown.body, measurements });
            if (shown === request && table.selected === i) draw(i, plot);
        } catch (error) {
            showError(error.message);
        }
    }

    initCopy($("e-copy"), () => table.copyRows());

    // Ready for the next specimen: the typed measurements and the result go;
    // the reference groups, the sides and the settings stay.
    $("e-clear").addEventListener("click", () => {
        const fields = [...numberFields($("e-values"))];
        for (const field of fields) field.value = "";
        $("e-results").hidden = true;
        fields[0]?.focus();
    });

    $("e-form").addEventListener("submit", async (event) => {
        event.preventDefault();
        const body = { references: labels(), sides: sidesOf($("e-values")), ...form.settings(), values: entered($("e-values")) };
        progress.show("Fitting models...");
        progress.set(50, "Fitting models...");
        try {
            const result = await postJSON("api/estimate", body);
            request = { body, results: result.results };
            markRun($("e-results"));
            table.show(result.results, result.selected);
            draw(result.selected, result.plot);
        } catch (error) {
            showError(error.message);
        } finally {
            progress.hide();
        }
    });

    setChoices(selects.reference, reference.labels(), meta.default_references);
    referenceChanged();
}
