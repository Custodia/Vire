const zones = {
  1: { name: "Recovery", fill: "fill-training-zone-1", bg: "bg-training-zone-1" },
  2: { name: "Endurance", fill: "fill-training-zone-2", bg: "bg-training-zone-2" },
  3: { name: "Tempo", fill: "fill-training-zone-3", bg: "bg-training-zone-3" },
  4: { name: "Threshold", fill: "fill-training-zone-4", bg: "bg-training-zone-4" },
  5: { name: "VO2 max", fill: "fill-training-zone-5", bg: "bg-training-zone-5" },
};

/** The name and colour classes of a training zone from 1 to 5, or null. */
export function zone(number) {
  return zones[number] ?? null;
}
