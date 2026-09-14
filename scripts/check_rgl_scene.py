"""Browser smoke test for an exported RGL scene; uses installed Chrome."""
import sys
from pathlib import Path

from playwright.sync_api import sync_playwright

scene = Path(sys.argv[1]).resolve()
output = Path("tmp/output/rgl-browser-check")
output.mkdir(parents=True, exist_ok=True)
with sync_playwright() as playwright:
    browser = playwright.chromium.launch(channel="chrome", headless=True)
    page = browser.new_page(viewport={"width": 850, "height": 850})
    errors = []
    page.on("pageerror", lambda error: errors.append(str(error)))
    page.goto(scene.as_uri())
    page.wait_for_function("document.querySelector('.rglWebGL')?.rglinstance?.gl")
    page.wait_for_timeout(500)
    status = page.evaluate("""() => {
      const r = document.querySelector('.rglWebGL').rglinstance;
      return {lost: r.gl.isContextLost(), error: r.gl.getError(),
              tags: Object.values(r.scene.objects).map(o => o.material?.tag)};
    }""")
    assert not status["lost"] and status["error"] == 0, status
    assert all(tag in status["tags"] for tag in ("panels", "edges", "label")), status
    matrix = "JSON.stringify(document.querySelector('.rglWebGL').rglinstance.getObj(document.querySelector('.rglWebGL').rglinstance.scene.rootSubscene).par3d.userMatrix)"
    before = page.evaluate(matrix)
    assert before is not None, "Scene has no camera rotation matrix"
    page.screenshot(path=str(output / "before.png"))
    bounds = page.locator("canvas").bounding_box()
    page.mouse.move(bounds["x"] + 350, bounds["y"] + 400)
    page.mouse.down()
    page.mouse.move(bounds["x"] + 500, bounds["y"] + 460, steps=20)
    page.mouse.up()
    page.wait_for_timeout(300)
    after = page.evaluate(matrix)
    assert before != after, "Dragging did not rotate the scene"
    page.screenshot(path=str(output / "after.png"))
    assert not errors, errors
    browser.close()
print("RGL WebGL context, panel/edge/texture objects, and interactive rotation passed.")
