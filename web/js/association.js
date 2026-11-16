// Association tab: is a known stature consistent with a specimen's bones?
// What is entered is one model, every measurement of every bone summed. With
// more than one bone, each bone is also tested on its own, a row apiece under
// the model's: bones that fit together need not each fit.

import {
    $, postJSON, showError, progress, makeSelect, boneName, setChoices, valuesOf, renderBones, entered, numberFields,
    sidesOf, initSharedSide, initSettings, initCopy, markRun, statTile, drawRegression, fixed, unitShort,
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
        element: makeSelect("a-element", () => elementsChanged(), boneName),
    };
    // Each bone has its own side. The Side buttons over the list set them
    // all, and show the one side they share, or neither when they differ.
    const sides = initSharedSide("a-side", $("a-values"));
    // the unit is chosen beside the known stature, not in the settings
    const form = initSettings("a-");

    // The chosen elements head to toe, whatever order they were chosen in:
    // in the list of fields and in the tags over it
    function elementsChanged() {
        const chosen = valuesOf(selects.element);
        const ordered = reference.elements(labels()).filter((bone) => chosen.includes(bone));
        if (ordered.join() !== chosen.join()) selects.element.setValue(ordered, true);
        const bones = ordered.map((bone) => ({ bone, codes: reference.measurements(labels(), bone) }));
        renderBones($("a-values"), bones, reference, sides.value());
        sides.show();
    }

    // The elements chosen stay where the groups still have them; with none
    // left, the first is chosen
    function referenceChanged() {
        const offered = reference.elements(labels());
        const kept = valuesOf(selects.element).filter((bone) => offered.includes(bone));
        setChoices(selects.element, offered, kept.length ? kept : offered.slice(0, 1));
        elementsChanged();
    }

    // The summary tiles and plot for one row of the result: the model, or a bone alone
    function draw(result, body, i) {
        const { columns, rows } = result.results;
        const cell = (name) => rows[i][columns.indexOf(name)];
        const unit = unitShort(body.unit);
        const interval = `${Math.round(body.interval * 100)}%`;
        $("a-summary").replaceChildren(
            statTile(["p-value", fixed(cell("p"), 3)]),
            statTile(["Expected measurement", fixed(cell("Point estimate"), 2), "mm"]),
            statTile([`${interval} prediction interval`, `${fixed(cell("Lower"), 2)} – ${fixed(cell("Upper"), 2)}`, "mm"]),
            statTile(["Reference sample", cell("n")]));
        drawRegression("a-plot", [result.plot, ...result.bone_plots][i], { x: cell("Known stature"), y: cell("Value") },
            { x: `Stature (${unit})`, y: "Summed measurements (mm)" });
    }

    function renderResult(result, body) {
        markRun($("a-results"));
        const { columns, rows } = result.results;
        fillTable($("a-table"), result.results, PLACES, (i) => draw(result, body, i));
        lastTable = [columns, ...rows.map((r) => r.map((value, c) => cellText(columns[c], value, PLACES)))];
        draw(result, body, 0);
    }

    initCopy($("a-copy"), () => lastTable);

    // Ready for the next specimen: the typed measurements, the known stature and
    // the result go; the reference groups, the elements, the sides and the settings stay.
    $("a-clear").addEventListener("click", () => {
        const fields = [$("a-known"), ...numberFields($("a-values"))];
        for (const field of fields) field.value = "";
        $("a-results").hidden = true;
        $("a-known").focus();
    });

    $("a-form").addEventListener("submit", async (event) => {
        event.preventDefault();
        const known = $("a-known").value;
        const body = { references: labels(), sides: sidesOf($("a-values")), ...form.settings(),
            known_stature: known === "" ? null : Number(known), values: entered($("a-values")) };
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
