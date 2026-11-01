const disciplines = {
  swim: {
    label: "Swim",
    activity: "Swim",
    text: "text-discipline-swim",
    soft: "text-discipline-swim-soft",
    tint: "bg-discipline-swim-tint",
    edge: "border-discipline-swim-edge",
    tile: "bg-discipline-swim-tile",
    stroke: "stroke-discipline-swim-soft",
    border: "border-discipline-swim-soft",
  },
  bike: {
    label: "Bike",
    activity: "Ride",
    text: "text-discipline-bike",
    soft: "text-discipline-bike-soft",
    tint: "bg-discipline-bike-tint",
    edge: "border-discipline-bike-edge",
    tile: "bg-discipline-bike-tile",
    stroke: "stroke-discipline-bike-soft",
    border: "border-discipline-bike-soft",
  },
  run: {
    label: "Run",
    activity: "Run",
    text: "text-discipline-run",
    soft: "text-discipline-run-soft",
    tint: "bg-discipline-run-tint",
    edge: "border-discipline-run-edge",
    tile: "bg-discipline-run-tile",
    stroke: "stroke-discipline-run-soft",
    border: "border-discipline-run-soft",
  },
  strength: {
    label: "Strength",
    activity: "Strength",
    text: "text-discipline-strength",
    soft: "text-discipline-strength-soft",
    tint: "bg-discipline-strength-tint",
    edge: "border-discipline-strength-edge",
    tile: "bg-discipline-strength-tile",
    stroke: "stroke-discipline-strength-soft",
    border: "border-discipline-strength-soft",
  },
  other: {
    label: "Other",
    activity: "Activity",
    text: "text-discipline-other",
    soft: "text-discipline-other-soft",
    tint: "bg-discipline-other-tint",
    edge: "border-discipline-other-edge",
    tile: "bg-discipline-other-tile",
    stroke: "stroke-discipline-other-soft",
    border: "border-discipline-other-soft",
  },
};

/**
 * The label, the name of an activity in it and the colour classes of a
 * discipline; an unknown one reads as other.
 */
export function discipline(name) {
  return disciplines[name] ?? disciplines.other;
}
