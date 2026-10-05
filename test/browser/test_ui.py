"""Drives the real page in a headless browser against a running server.

    docker run --rm --network host --user "$(id -u):$(id -g)" -e HOME=/tmp \
        -v "$PWD:/app:z" -w /app mcr.microsoft.com/playwright/python:v1.49.0-jammy \
        sh -c "pip install -q playwright==1.49.0 && python test/browser/test_ui.py [URL]"

URL defaults to http://127.0.0.1:3838/. What the page shows is compared with
what the API returns for the same input; the API itself is tested in
test/server. Screenshots are written to test/browser/screens.
"""
import json
import pathlib
import sys
import urllib.error
import urllib.request

from playwright.sync_api import expect, sync_playwright

ROOT = pathlib.Path(__file__).resolve().parents[2]
SCREENS = ROOT / "test" / "browser" / "screens"
URL = sys.argv[1] if len(sys.argv) > 1 else "http://127.0.0.1:3838/"

REFERENCE = ["Trotter white male"]
ESTIMATION = {"hum_01": 330, "fem_01": 450, "tib_01": 370}
# the places each number is shown with, as the page rounds them
PLACES = {"PI": 2, "Value": 2, "Point estimate": 2, "Lower": 2, "Upper": 2, "Intercept": 2, "R²": 3}


def api(path, body):
    request = urllib.request.Request(URL + path, json.dumps(body).encode(), {"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(request) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        return json.load(error)


def shown(column, value, places):
    if value is None:
        return ""
    if column in places:
        return f"{value:.{places[column]}f}"
    # as JavaScript writes a number: 67, not 67.0
    return str(int(value)) if isinstance(value, float) and value.is_integer() else str(value)


def table_cells(page, selector):
    """The rows of a table as the page shows them, cell by cell."""
    return page.eval_on_selector_all(f"{selector} tbody tr",
                                     "rows => rows.map(r => [...r.cells].map(c => c.textContent))")


def expected_rows(result, order, places):
    columns = result["results"]["columns"]
    keep = [i for i, c in enumerate(columns) if c != "Reference"]
    return [[shown(columns[i], result["results"]["rows"][r][i], places) for i in keep] for r in order]


def fill(page, prefix, values):
    for code, value in values.items():
        page.fill(f"#{prefix}-values-{code}", str(value))


def choose(page, select_id, value):
    """Picks a value in a Tom Select dropdown as a user would."""
    page.click(f".ts-wrapper:has(#{select_id}-ts-control) .ts-control")
    page.click(f"#{select_id}-ts-dropdown .option[data-value='{value}']")


def run(page):
    SCREENS.mkdir(parents=True, exist_ok=True)
    page.goto(URL)
    expect(page.locator("#app-content")).to_be_visible()
    expect(page.locator("#version")).to_have_text("v " + open(ROOT / "VERSION").read().strip())
    assert page.evaluate("document.getElementById('e-reference').tomselect.getValue()") == REFERENCE
    # every stature measurement the default group has, head to toe
    codes = page.eval_on_selector_all("#e-values input", "inputs => inputs.map(i => i.dataset.code)")
    assert codes == ["hum_01", "rad_01", "uln_01", "fem_01", "fem_02", "tib_01", "fib_01"], codes

    # ---------- estimation ----------
    fill(page, "e", ESTIMATION)
    page.click("#e-process")
    expect(page.locator("#e-results")).to_be_visible()
    body = {"references": REFERENCE, "side": "left", "interval": 0.95, "unit": "Inches", "bootstrap": False,
            "values": {code: ESTIMATION.get(code) for code in codes}}
    result = api("api/estimate", body)
    rows = result["results"]["rows"]
    places = {**PLACES, "Slope": 5}
    # sorted by PI, narrowest first; ties in the server's order
    order = sorted(range(len(rows)), key=lambda i: (rows[i][0], i))
    assert table_cells(page, "#e-table") == expected_rows(result, order, places)
    selected = result["selected"]
    expect(page.locator("#e-table tr.selected td").nth(1)).to_have_text(rows[selected][1])
    tiles = page.locator("#e-summary .stat-value")
    expect(tiles.nth(0)).to_have_text(f"{rows[selected][3]:.2f}in")
    # the sample size says which groups on hover
    assert page.get_attribute("#e-table tr.selected td:nth-child(7)", "data-tooltip") == rows[selected][11]
    page.screenshot(path=str(SCREENS / "estimation.png"), full_page=True)

    # another model: its row turns gold and the summary follows
    other = order[-1]
    page.locator("#e-table tbody tr").nth(len(order) - 1).click()
    expect(page.locator("#e-table tr.selected td").nth(1)).to_have_text(rows[other][1])
    expect(tiles.nth(3)).to_have_text(rows[other][1])
    expect(tiles.nth(0)).to_have_text(f"{rows[other][3]:.2f}in")

    # Copy takes the chosen model alone, under the column headings
    page.context.grant_permissions(["clipboard-read", "clipboard-write"])
    page.click("#e-copy")
    expect(page.locator("#e-copy span")).to_have_text("Copied")
    copied = [line.split("\t") for line in page.evaluate("navigator.clipboard.readText()").split("\n")]
    columns = result["results"]["columns"]
    assert copied == [columns, [shown(c, v, places) for c, v in zip(columns, rows[other])]], copied

    # sorting by a column, then back
    page.click("#e-table th:has-text('Value')")
    by_value = sorted(range(len(rows)), key=lambda i: (rows[i][2], i))
    assert table_cells(page, "#e-table") == expected_rows(result, by_value, places)

    # centimetres, a narrower interval, from the settings
    page.click("label[for='e-unit-cm']")
    page.click("label[for='e-interval-90']")
    page.click("#e-process")
    expect(page.locator("#e-results")).to_have_attribute("data-run", "2")
    cm = api("api/estimate", {**body, "unit": "Centimeters", "interval": 0.9})
    cm_rows = cm["results"]["rows"]
    expect(tiles.nth(0)).to_have_text(f"{cm_rows[cm['selected']][3]:.2f}cm")

    # Clear empties the fields and hides the result; nothing typed is an error
    page.click("#e-clear")
    expect(page.locator("#e-results")).to_be_hidden()
    page.click("#e-process")
    expect(page.locator("#error-text")).to_have_text("Enter at least one measurement")
    page.click("#error-modal button")

    # ---------- association ----------
    page.click("#nav-association")
    choose(page, "a-element", "femur")
    page.fill("#a-known", "67")
    fill(page, "a", {"fem_01": 450})
    page.click("#a-process")
    expect(page.locator("#a-results")).to_be_visible()
    association = api("api/associate", {"references": REFERENCE, "element": "femur", "side": "left", "interval": 0.95,
                                        "unit": "Inches", "known_stature": 67, "values": {"fem_01": 450}})
    a_places = {**PLACES, "Slope": 3, "Intercept": 3, "p": 3}
    cells, want = table_cells(page, "#a-table"), expected_rows(association, [0], a_places)
    assert cells == want, (cells, want)
    columns = association["results"]["columns"]
    expect(page.locator("#a-summary .stat-value").nth(0)).to_have_text(f"{association['results']['rows'][0][columns.index('p')]:.3f}")
    page.screenshot(path=str(SCREENS / "association.png"), full_page=True)

    # the unit is chosen beside the known stature, and the result follows it
    page.click("label[for='a-unit-cm']")
    page.fill("#a-known", "170")
    page.click("#a-process")
    expect(page.locator("#a-results")).to_have_attribute("data-run", "2")
    in_cm = api("api/associate", {"references": REFERENCE, "element": "femur", "side": "left", "interval": 0.95,
                                  "unit": "Centimeters", "known_stature": 170, "values": {"fem_01": 450}})
    assert table_cells(page, "#a-table") == expected_rows(in_cm, [0], a_places)
    page.fill("#a-known", "")
    page.click("#a-process")
    expect(page.locator("#error-text")).to_have_text("Enter a known stature")


with sync_playwright() as playwright:
    browser = playwright.chromium.launch()
    page = browser.new_page(viewport={"width": 1500, "height": 1000})
    errors = []
    page.on("pageerror", lambda error: errors.append(str(error)))
    run(page)
    assert not errors, errors
    browser.close()
print("Browser test passed")
