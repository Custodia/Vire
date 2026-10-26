const disciplines = {
  swim: {
    label: "Swim",
    text: "text-discipline-swim",
    tint: "bg-discipline-swim-tint",
    edge: "border-discipline-swim-edge",
    tile: "bg-discipline-swim-tile",
  },
  bike: {
    label: "Bike",
    text: "text-discipline-bike",
    tint: "bg-discipline-bike-tint",
    edge: "border-discipline-bike-edge",
    tile: "bg-discipline-bike-tile",
  },
  run: {
    label: "Run",
    text: "text-discipline-run",
    tint: "bg-discipline-run-tint",
    edge: "border-discipline-run-edge",
    tile: "bg-discipline-run-tile",
  },
  strength: {
    label: "Strength",
    text: "text-discipline-strength",
    tint: "bg-discipline-strength-tint",
    edge: "border-discipline-strength-edge",
    tile: "bg-discipline-strength-tile",
  },
  other: {
    label: "Other",
    text: "text-discipline-other",
    tint: "bg-discipline-other-tint",
    edge: "border-discipline-other-edge",
    tile: "bg-discipline-other-tile",
  },
};

/** The label and colour classes of a discipline; an unknown one reads as other. */
export function discipline(name) {
  return disciplines[name] ?? disciplines.other;
}
