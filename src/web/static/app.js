// Light status polling — the app works fine without this.
function initNavMenu() {
  const topbar = document.querySelector(".topbar");
  const toggle = document.querySelector(".nav-toggle");
  const nav = document.getElementById("primary-nav");
  if (!topbar || !toggle || !nav) return;

  const closeNav = () => {
    topbar.classList.remove("nav-open");
    toggle.setAttribute("aria-expanded", "false");
    toggle.setAttribute("aria-label", "Open navigation menu");
  };

  const openNav = () => {
    topbar.classList.add("nav-open");
    toggle.setAttribute("aria-expanded", "true");
    toggle.setAttribute("aria-label", "Close navigation menu");
  };

  toggle.addEventListener("click", () => {
    if (topbar.classList.contains("nav-open")) {
      closeNav();
    } else {
      openNav();
    }
  });

  nav.addEventListener("click", (event) => {
    if (event.target instanceof Element && event.target.closest("a, button")) closeNav();
  });

  document.addEventListener("click", (event) => {
    if (!topbar.contains(event.target)) closeNav();
  });

  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape") closeNav();
  });

  const desktopQuery = window.matchMedia("(min-width: 721px)");
  const syncDesktop = (event) => {
    if (event.matches) closeNav();
  };

  if (desktopQuery.addEventListener) {
    desktopQuery.addEventListener("change", syncDesktop);
  } else {
    desktopQuery.addListener(syncDesktop);
  }
}

async function pattyPoll() {
  try {
    const res = await fetch("/api/status");
    if (!res.ok) return;
    const data = await res.json();

    const caddy = document.getElementById("caddy-status");
    if (caddy) {
      caddy.textContent = data.caddy.found
        ? (data.caddy.running ? "running" : "found, not running")
        : "not found";
      caddy.className = "badge " + (data.caddy.running ? "ok" : "warn");
    }

    for (const p of data.profiles) {
      const service = document.querySelector(`[data-service="${CSS.escape(p.id)}"]`);
      if (service) {
        service.textContent = p.service;
        service.className = "badge " + (p.service === "running" ? "ok" : "off");
      }
      const route = document.querySelector(`[data-route="${CSS.escape(p.id)}"]`);
      if (route) {
        route.textContent = "route " + (p.route_enabled ? "enabled" : "disabled");
        route.className = "badge " + (p.route_enabled ? "ok" : "off");
      }
      const health = document.querySelector(`[data-health="${CSS.escape(p.id)}"]`);
      if (health) {
        health.textContent = p.health_label;
        health.title = p.health_detail;
        const healthClass = p.health === "healthy"
          ? "ok"
          : (p.health === "unhealthy" ? "error" : (p.health === "unknown" ? "warn" : "off"));
        health.className = "badge " + healthClass;
      }
    }
  } catch (_) {
    // server briefly unavailable; try again next tick
  }
}

initNavMenu();

if (document.getElementById("caddy-status")) {
  setInterval(pattyPoll, 5000);
}
