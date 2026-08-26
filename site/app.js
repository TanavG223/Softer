(() => {
  "use strict";

  const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  const routeCopy = {
    safety: {
      kicker: "Deterministic bypass",
      title: "Danger signs never wait for AI.",
      copy:
        "Reviewed danger-sign phrases route directly to static CDC emergency instructions. Retrieval and model generation do not run.",
      rounds: "0",
      rule: "Static safety copy",
      stop: "Immediate",
      activeStages: [],
      emphasizedStages: [],
    },
    single: {
      kicker: "Single retrieval",
      title: "One bounded pass, then evidence or abstention.",
      copy:
        "Sparse and dense candidates are filtered, fused, reranked, budgeted, and checked. At most eight cited passages can reach the answer.",
      rounds: "1",
      rule: "Citations required",
      stop: "Verified support or failure",
      activeStages: ["scope", "sparse", "dense", "fusion", "rerank", "budget", "verify"],
      emphasizedStages: ["scope", "verify"],
    },
    iterative: {
      kicker: "Adaptive retrieval",
      title: "Complex requests get more search—not unlimited autonomy.",
      copy:
        "The original question is preserved across at most three rounds, six subqueries, 100 unique candidates, and eight total actions. The system then stops and abstains.",
      rounds: "≤ 3",
      rule: "≤ 6 subqueries",
      stop: "≤ 8 actions, then abstain",
      activeStages: ["scope", "sparse", "dense", "fusion", "rerank", "budget", "verify"],
      emphasizedStages: ["scope", "fusion", "budget", "verify"],
    },
  };

  const routeFields = {
    kicker: document.querySelector("#route-kicker"),
    title: document.querySelector("#route-title"),
    copy: document.querySelector("#route-copy"),
    rounds: document.querySelector("#route-rounds"),
    rule: document.querySelector("#route-rule"),
    stop: document.querySelector("#route-stop"),
  };

  const updateRoute = (button) => {
    const key = button.dataset.route;
    const selected = routeCopy[key];

    if (!selected) return;

    document.querySelectorAll(".route-button").forEach((candidate) => {
      const active = candidate === button;
      candidate.classList.toggle("is-active", active);
      candidate.setAttribute("aria-pressed", String(active));
    });

    Object.entries(routeFields).forEach(([field, element]) => {
      if (element) element.textContent = selected[field];
    });

    document.querySelectorAll(".pipeline-map [data-stage]").forEach((stage) => {
      const stageName = stage.dataset.stage;
      stage.classList.toggle("is-muted", !selected.activeStages.includes(stageName));
      stage.classList.toggle("is-emphasized", selected.emphasizedStages.includes(stageName));
    });
  };

  document.querySelectorAll(".route-button").forEach((button) => {
    button.addEventListener("click", () => updateRoute(button));
  });

  const personaFields = {
    age: document.querySelector("#persona-age"),
    operator: document.querySelector("#persona-operator"),
    view: document.querySelector("#persona-view"),
    gate: document.querySelector("#persona-gate"),
  };

  const updatePersona = (button) => {
    document.querySelectorAll(".age-stop").forEach((candidate) => {
      const selected = candidate === button;
      candidate.classList.toggle("is-selected", selected);
      candidate.setAttribute("aria-pressed", String(selected));
    });

    personaFields.age.textContent = button.dataset.age;
    personaFields.operator.textContent = button.dataset.operator;
    personaFields.view.textContent = button.dataset.view;
    personaFields.gate.textContent = button.dataset.gate;
  };

  document.querySelectorAll(".age-stop").forEach((button) => {
    button.addEventListener("click", () => updatePersona(button));
  });

  const iosStageCopy = {
    download: {
      kicker: "Stage 01 · explicit transfer",
      title: "The user chooses when the model pack arrives.",
      copy:
        "Four frozen files—BGE and MiniLM ONNX weights plus their tokenizers—download in the foreground from immutable-revision HTTPS URLs on allowlisted hosts. PaceBack sends no profile, health, symptom, query, or care-plan fields.",
      stats: [
        ["Pack size", "157,716,998 bytes"],
        ["Choice", "Wi-Fi or cellular"],
        ["Session", "Foreground only"],
      ],
    },
    verify: {
      kicker: "Stage 02 · cryptographic receipt",
      title: "Every byte must earn activation.",
      copy:
        "A bundled Ed25519 public key verifies the signed manifest. Exact expected size and SHA-256 then verify all four artifacts; a mismatch fails closed and never replaces a working pack.",
      stats: [
        ["Manifest", "Ed25519 signed"],
        ["Artifacts", "4 of 4 required"],
        ["Failure", "Nothing activated"],
      ],
    },
    ready: {
      kicker: "Stage 03 · local evidence",
      title: "Ready offline means no silent fallback.",
      copy:
        "Verified BGE and MiniLM ONNX models search seven bundled curated public-source summaries. Age filtering happens before retrieval; an invalid pack, corpus, inference, or locator check produces an explicit failure or abstention.",
      stats: [
        ["Age filter", "Before retrieval"],
        ["Search", "Hybrid + rerank"],
        ["Cloud fallback", "None"],
      ],
    },
  };

  const iosFields = {
    kicker: document.querySelector("#ios-stage-kicker"),
    title: document.querySelector("#ios-stage-title"),
    copy: document.querySelector("#ios-stage-copy"),
    statLabels: [1, 2, 3].map((index) => document.querySelector(`#ios-stat-label-${index}`)),
    statValues: [1, 2, 3].map((index) => document.querySelector(`#ios-stat-value-${index}`)),
  };

  const updateIosStage = (button) => {
    const selected = iosStageCopy[button.dataset.iosStage];
    if (!selected) return;

    document.querySelectorAll(".setup-stage").forEach((candidate) => {
      const active = candidate === button;
      candidate.classList.toggle("is-active", active);
      candidate.setAttribute("aria-pressed", String(active));
    });

    if (iosFields.kicker) iosFields.kicker.textContent = selected.kicker;
    if (iosFields.title) iosFields.title.textContent = selected.title;
    if (iosFields.copy) iosFields.copy.textContent = selected.copy;

    selected.stats.forEach(([label, value], index) => {
      if (iosFields.statLabels[index]) iosFields.statLabels[index].textContent = label;
      if (iosFields.statValues[index]) iosFields.statValues[index].textContent = value;
    });
  };

  document.querySelectorAll(".setup-stage").forEach((button) => {
    button.addEventListener("click", () => updateIosStage(button));
  });

  const revealTargets = document.querySelectorAll(".spine-section, .purpose-band");

  if (!reduceMotion && "IntersectionObserver" in window) {
    document.body.classList.add("reveal-ready");
    const revealObserver = new IntersectionObserver(
      (entries, observer) => {
        entries.forEach((entry) => {
          if (!entry.isIntersecting) return;
          entry.target.classList.add("is-visible");
          observer.unobserve(entry.target);
        });
      },
      { rootMargin: "0px 0px -8%", threshold: 0.08 },
    );

    revealTargets.forEach((target) => revealObserver.observe(target));
  } else {
    revealTargets.forEach((target) => target.classList.add("is-visible"));
  }

  const initialRoute = document.querySelector(".route-button.is-active");
  if (initialRoute) updateRoute(initialRoute);

  const initialIosStage = document.querySelector(".setup-stage.is-active");
  if (initialIosStage) updateIosStage(initialIosStage);
})();
