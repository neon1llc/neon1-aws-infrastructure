// site/functions/signin.js - The dev sign-in's look: the family and mode saved on this origin ("neon1.style", "neon1.mode", as the site and 1NEON keep them),
// Sentinel light until picked, painted before the first frame. dev-auth.mjs puts it in the page; the header policy allows exactly these bytes (sign-in.tf).
const root = document.documentElement;
const get = (k) => { try { return localStorage.getItem(k); } catch { return null; } };
const set = (k, v) => { try { localStorage.setItem(k, v); } catch {} };
const family = () => (["matrix", "stylized"].includes(get("neon1.style")) ? "matrix" : "sentinel");
const dark = () => get("neon1.mode") === "dark";
let held = null;
let rain = null;
function paint() {
  const style = held?.style ?? family(), night = held?.dark ?? dark();
  if (style === "sentinel") root.setAttribute("data-style", "sentinel"); else root.removeAttribute("data-style");
  root.setAttribute("data-theme", night ? "matrix" : "awake");
  document.querySelector(".theme-sw")?.setAttribute("aria-checked", String(night));
  document.querySelectorAll("[data-look]").forEach((b) => b.setAttribute("aria-pressed", String(b.dataset.look === style)));
  // The rain falls only in Matrix dark; it loads once and rests in the other looks
  const wet = style === "matrix" && night && document.getElementById("rain");
  if (wet && !rain) rain = import("/shared/rain.js").then((m) => m.rain({ canvas: document.getElementById("rain"), lens: document.getElementById("lens"), panes: () => document.querySelectorAll(".panel, .n1-logo") })).catch(() => null);
  rain?.then((r) => r?.setRunning(Boolean(wet)));
}
function pick(style, night) {
  set("neon1.style", style);
  set("neon1.mode", night ? "dark" : "light");
  set("neon1.theme.shared", "1");
  // With storage blocked the pick still holds on this page
  held = family() === style && dark() === night ? null : { style, dark: night };
  paint();
}
paint();
addEventListener("DOMContentLoaded", () => {
  const now = () => ({ style: held?.style ?? family(), dark: held?.dark ?? dark() });
  document.querySelector(".theme-sw").addEventListener("click", () => pick(now().style, !now().dark));
  document.querySelectorAll("[data-look]").forEach((b) => b.addEventListener("click", () => pick(b.dataset.look, now().dark)));
  paint();
});
addEventListener("storage", paint);
addEventListener("pageshow", paint);
