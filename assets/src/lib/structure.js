const kindLabels = {
  warmup: "warm-up",
  work: "work",
  recovery: "recovery",
  cooldown: "cool-down",
  rest: "rest",
};

/** The structure's steps, or an empty list. */
export function stepsOf(structure) {
  return Array.isArray(structure?.steps) ? structure.steps : [];
}

/** The steps with every repeat written out, in the order they are done. */
export function flattenSteps(steps) {
  return steps.flatMap((step) =>
    step.repeat
      ? Array.from({ length: step.repeat }, () => flattenSteps(step.steps)).flat()
      : [step],
  );
}

export function totalSeconds(steps, kind) {
  return flattenSteps(steps)
    .filter((step) => !kind || step.kind === kind)
    .reduce((sum, step) => sum + step.seconds, 0);
}

/** The highest zone any step reaches, or null. */
export function peakZone(steps) {
  const zones = flattenSteps(steps)
    .map((step) => step.zone)
    .filter(Boolean);
  return zones.length ? Math.max(...zones) : null;
}

export function kindLabel(kind) {
  return kindLabels[kind];
}

/** The steps in words, such as 10′ warm-up in Z1, 4 × (4′ work in Z4, 2′ recovery). */
export function describeSteps(steps) {
  return steps.map(describeStep).join(", ");
}

function describeStep(step) {
  if (step.repeat) return `${step.repeat} × (${describeSteps(step.steps)})`;
  const minutes = Math.round((step.seconds / 60) * 10) / 10;
  const zone = step.zone ? ` in Z${step.zone}` : "";
  return `${minutes}′ ${kindLabel(step.kind)}${zone}`;
}
