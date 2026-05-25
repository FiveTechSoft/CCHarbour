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
      hue:           hue,
      primary:       "hsl(" + hue + ", " + s + ", " + l + ")",
      primaryLight:  "hsl(" + hue + ", " + s + ", 56%)",
      primaryDark:   "hsl(" + hue + ", " + s + ", 28%)",
      accent:        "hsl(" + ((hue + 35) % 360) + ", 68%, 48%)",
      accentTrans:   "hsla(" + ((hue + 35) % 360) + ", 68%, 48%, 0.20)"
    };
  }

  function applyPalette(p) {
    // Set on BOTH html and (once available) body. Material defines the
    // palette vars under `body[data-md-color-primary=teal]`, an
    // attribute selector that beats an inline style on html. An inline
    // style on body itself has highest specificity for the body subtree,
    // so writing both makes the override stick regardless of theme.
    var targets = [document.documentElement];
    if (document.body) targets.push(document.body);
    var pairs = [
      ["--md-primary-fg-color",            p.primary],
      ["--md-primary-fg-color--light",     p.primaryLight],
      ["--md-primary-fg-color--dark",      p.primaryDark],
      ["--md-accent-fg-color",             p.accent],
      ["--md-accent-fg-color--transparent", p.accentTrans],
      ["--md-typeset-a-color",             p.accent],
      // Playground page does not use Material; expose the same hue
      // through its own variable names so its banner / chips / focus
      // glow track the random colour too.
      ["--accent",        p.primary],
      ["--accent-bright", p.primaryLight],
      ["--accent-deep",   p.primaryDark],
      ["--accent-purple", p.accent],
      ["--accent-glow",        "hsla(" + p.hue + ", 62%, 50%, 0.22)"],
      ["--accent-glow-soft",   "hsla(" + p.hue + ", 62%, 50%, 0.10)"]
    ];
    for (var i = 0; i < targets.length; i++) {
      for (var j = 0; j < pairs.length; j++) {
        targets[i].style.setProperty(pairs[j][0], pairs[j][1]);
      }
    }
  }

  // Apply ASAP -- once on script load, and again on DOMContentLoaded in case
  // the script lands before the head finishes parsing custom variables.
  var palette = pickPalette();
  applyPalette(palette);
  document.addEventListener("DOMContentLoaded", function () { applyPalette(palette); });
})();
