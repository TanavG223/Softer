const needs = [...document.querySelectorAll(".need-stop")];
const selected = document.querySelector("#need-selected");
const tool = document.querySelector("#need-tool");
const reason = document.querySelector("#need-reason");
const alternatives = document.querySelector("#need-alternatives");

for (const button of needs) {
  button.addEventListener("click", () => {
    for (const other of needs) {
      const active = other === button;
      other.classList.toggle("is-selected", active);
      other.setAttribute("aria-pressed", String(active));
    }
    selected.textContent = button.dataset.need;
    tool.textContent = button.dataset.tool;
    reason.textContent = button.dataset.reason;
    alternatives.textContent = button.dataset.alternatives;
  });
}

const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
const revealItems = [...document.querySelectorAll("[data-reveal]")];
if (reducedMotion || !("IntersectionObserver" in window)) {
  revealItems.forEach((item) => item.classList.add("is-visible"));
} else {
  const observer = new IntersectionObserver((entries) => {
    for (const entry of entries) {
      if (entry.isIntersecting) {
        entry.target.classList.add("is-visible");
        observer.unobserve(entry.target);
      }
    }
  }, { threshold: 0.12 });
  revealItems.forEach((item) => observer.observe(item));
}
