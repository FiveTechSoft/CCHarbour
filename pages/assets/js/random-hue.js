// random-hue.js -- recolours the Material theme on every page load.
//
// Material exposes its primary/accent colour as the CSS custom properties
// --md-primary-fg-color, --md-primary-fg-color--light, --md-primary-fg-color--dark
// and --md-accent-fg-color (plus a transparent variant). We override them
// with a fresh HSL hue every visit, keeping saturation/lightness in the
// teal-ish band Material expects so the contrast against the rest of the
// theme stays readable in both light and slate modes.
//
// The colour is generated once per page load (no animation), so a refresh
// produces a new palette but in-page interactions stay on a stable tone.

(function () {
  function pickPalette() {
    var hue = Math.floor(Math.random() * 360);
    var s = "62%";
    var l = "42%";
    return {
      primary:       "hsl(" + hue + ", " + s + ", " + l + ")",
      primaryLight:  "hsl(" + hue + ", " + s + ", 56%)",
      primaryDark:   "hsl(" + hue + ", " + s + ", 28%)",
      accent:        "hsl(" + ((hue + 35) % 360) + ", 68%, 48%)",
      accentTrans:   "hsla(" + ((hue + 35) % 360) + ", 68%, 48%, 0.20)"
    };
  }

  function applyPalette(p) {
    var root = document.documentElement;
    root.style.setProperty("--md-primary-fg-color",         p.primary);
    root.style.setProperty("--md-primary-fg-color--light",  p.primaryLight);
    root.style.setProperty("--md-primary-fg-color--dark",   p.primaryDark);
    root.style.setProperty("--md-accent-fg-color",          p.accent);
    root.style.setProperty("--md-accent-fg-color--transparent", p.accentTrans);
    // tweak the link colour too so it tracks the accent in body copy
    root.style.setProperty("--md-typeset-a-color",          p.accent);
  }

  // Apply ASAP -- once on script load, and again on DOMContentLoaded in case
  // the script lands before the head finishes parsing custom variables.
  var palette = pickPalette();
  applyPalette(palette);
  document.addEventListener("DOMContentLoaded", function () { applyPalette(palette); });
})();
