// Result tables. The whole result is in the browser (an estimation has at
// most a few hundred models), so sorting and paging are done here.

import { NUMERIC_COLUMNS, fixed } from "./common.js";

const PAGE_SIZES = [10, 25, 50];

// A cell as it is shown: numbers with the places they were rounded to
function cellText(column, value, places) {
    if (value === null || value === undefined) return "";
    return places[column] !== undefined ? fixed(value, places[column]) : String(value);
}

// The reference breakdown is not a column on screen: it shows when the
// sample size is hovered, and it is copied.
function fillRow(tr, columns, row, places) {
    const hidden = columns.indexOf("Reference");
    row.forEach((cell, index) => {
        if (index === hidden) return;
        const td = tr.insertCell();
        td.textContent = cellText(columns[index], cell, places);
        if (NUMERIC_COLUMNS.has(columns[index])) td.className = "num";
        if (columns[index] === "n" && hidden >= 0 && row[hidden]) td.dataset.tooltip = row[hidden];
    });
}

function fillHead(tr, columns) {
    const cells = [];
    for (const column of columns) {
        if (column === "Reference") continue;
        const th = document.createElement("th");
        th.textContent = column;
        if (NUMERIC_COLUMNS.has(column)) th.className = "num";
        tr.append(th);
        cells.push([th, columns.indexOf(column)]);
    }
    return cells;
}

// A one-row result
export function fillTable(table, results, places) {
    table.replaceChildren();
    fillHead(table.createTHead().insertRow(), results.columns);
    const body = table.createTBody();
    for (const row of results.rows) fillRow(body.insertRow(), results.columns, row, places);
}

// An estimation's models. Clicking a row chooses that model; `onSelect` is
// given its index in the server's order. Sorted by the first column (PI)
// to begin with, narrowest first.
export class ModelTable {
    constructor(container, places, onSelect) {
        this.container = container;
        this.places = places;
        this.onSelect = onSelect;
        container.innerHTML = `
            <div class="table-responsive"><table class="table table-striped result-table selectable"><thead><tr></tr></thead><tbody></tbody></table></div>
            <div class="table-footer">
                <div class="table-count"></div>
                <div class="table-paging">
                    <select class="form-select form-select-sm page-size" aria-label="Rows per page">
                        ${PAGE_SIZES.map((size) => `<option value="${size}">${size} per page</option>`).join("")}
                    </select>
                    <ul class="pagination pagination-sm"></ul>
                </div>
            </div>`;
        container.querySelector(".page-size").addEventListener("change", (event) => {
            this.limit = Number(event.target.value);
            this.offset = 0;
            this.render();
        });
        this.limit = PAGE_SIZES[0];
    }

    // New results: sorted by PI, on the page that holds the chosen model
    show(results, selected) {
        this.results = results;
        this.selected = selected;
        this.sort = 0;
        this.dir = "asc";
        this.order();
        this.offset = Math.floor(this.rows.indexOf(selected) / this.limit) * this.limit;
        this.render();
    }

    // Row indexes in display order; ties keep the server's order
    order() {
        const column = this.sort;
        const sign = this.dir === "asc" ? 1 : -1;
        const rows = this.results.rows;
        this.rows = rows.map((_, i) => i).sort((a, b) => {
            const x = rows[a][column], y = rows[b][column];
            const by = typeof x === "number" && typeof y === "number" ? x - y : String(x).localeCompare(String(y));
            return sign * by || a - b;
        });
    }

    render() {
        const { columns, rows } = this.results;
        const head = this.container.querySelector("thead tr");
        head.replaceChildren();
        for (const [th, index] of fillHead(head, columns)) {
            th.classList.add("sortable");
            if (this.sort === index) th.classList.add(`sorted-${this.dir}`);
            th.addEventListener("click", () => {
                this.dir = this.sort === index && this.dir === "asc" ? "desc" : "asc";
                this.sort = index;
                this.order();
                this.offset = 0;
                this.render();
            });
        }
        const body = this.container.querySelector("tbody");
        body.replaceChildren();
        for (const i of this.rows.slice(this.offset, this.offset + this.limit)) {
            const tr = body.insertRow();
            fillRow(tr, columns, rows[i], this.places);
            if (i === this.selected) tr.classList.add("selected");
            tr.addEventListener("click", () => {
                if (i === this.selected) return;
                this.selected = i;
                this.render();
                this.onSelect(i);
            });
        }
        this.renderFooter();
    }

    renderFooter() {
        const total = this.rows.length;
        const size = this.limit;
        const last = Math.min(this.offset + size, total);
        this.container.querySelector(".table-count").textContent =
            `Showing ${total ? this.offset + 1 : 0} to ${last} of ${total.toLocaleString()} models`;
        const pages = Math.max(1, Math.ceil(total / size));
        const current = Math.floor(this.offset / size) + 1;
        const list = this.container.querySelector(".pagination");
        list.replaceChildren();
        const add = (label, target, { active = false, disabled = false, name = "" } = {}) => {
            const item = document.createElement("li");
            item.className = "page-item" + (active ? " active" : "") + (disabled ? " disabled" : "");
            const link = document.createElement("button");
            link.type = "button";
            link.className = "page-link";
            link.textContent = label;
            if (name) link.setAttribute("aria-label", name);
            if (!disabled && !active) {
                link.addEventListener("click", () => {
                    this.offset = (target - 1) * size;
                    this.render();
                });
            }
            item.append(link);
            list.append(item);
        };
        add("‹", current - 1, { disabled: current === 1, name: "Previous page" });
        for (const number of pageNumbers(current, pages)) {
            if (number === null) add("…", 0, { disabled: true });
            else add(String(number), number, { active: number === current });
        }
        add("›", current + 1, { disabled: current === pages, name: "Next page" });
    }

    // What Copy puts on the clipboard: the chosen model as shown, with the
    // column headings and the reference breakdown
    copyRows() {
        const { columns, rows } = this.results;
        return [columns, rows[this.selected].map((cell, c) => cellText(columns[c], cell, this.places))];
    }
}

// 1 2 3 4 5 … 13, with the window following the current page
function pageNumbers(current, pages) {
    if (pages <= 7) return Array.from({ length: pages }, (_, i) => i + 1);
    if (current <= 4) return [1, 2, 3, 4, 5, null, pages];
    if (current >= pages - 3) return [1, null, pages - 4, pages - 3, pages - 2, pages - 1, pages];
    return [1, null, current - 1, current, current + 1, null, pages];
}

export { cellText };
