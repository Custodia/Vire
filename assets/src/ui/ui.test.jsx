import { describe, expect, test } from "vitest";
import { render, screen, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { sessions } from "../mocks/handlers.js";
import { Button } from "./Button.jsx";
import { CoachNote } from "./CoachNote.jsx";
import { DisciplineIcon } from "./DisciplineIcon.jsx";
import { Screen } from "./Screen.jsx";
import { Frame } from "./Frame.jsx";
import { PageHeader } from "./PageHeader.jsx";
import { SessionChip } from "./SessionChip.jsx";
import { SessionRow } from "./SessionRow.jsx";
import { Stat } from "./Stat.jsx";
import { StatusChip } from "./StatusChip.jsx";
import { TextField } from "./TextField.jsx";
import { TrainingZoneBadge } from "./TrainingZoneBadge.jsx";
import { WorkoutProfile } from "./WorkoutProfile.jsx";

describe("Stat", () => {
  test("shows the number over its label", () => {
    render(<Stat value="35′" label="Duration" size="md" />);

    expect(screen.getByText("35′")).toBeInTheDocument();
    expect(screen.getByText("Duration")).toBeInTheDocument();
  });

  test("shows what the number counts towards", () => {
    render(<Stat value={7} of={11} label="sessions done this week" />);

    expect(screen.getByText("sessions done this week").previousSibling).toHaveTextContent(
      "7 of 11",
    );
  });
});

describe("StatusChip", () => {
  test.each([
    ["done", "✓ Done"],
    ["skipped", "✕ Skipped"],
    ["upcoming", "Upcoming"],
    ["rest", "Rest"],
  ])("names the %s state", (state, text) => {
    const { container } = render(<StatusChip state={state} />);

    expect(container).toHaveTextContent(text);
  });
});

describe("DisciplineIcon", () => {
  test.each([
    ["swim", "Swim"],
    ["bike", "Bike"],
    ["run", "Run"],
    ["strength", "Strength"],
    ["other", "Other"],
    ["rowing", "Other"],
  ])("draws %s with the name %s", (discipline, name) => {
    render(<DisciplineIcon discipline={discipline} />);

    expect(screen.getByRole("img", { name })).toBeInTheDocument();
  });
});

describe("TrainingZoneBadge", () => {
  test("shows the zone and names it", () => {
    render(<TrainingZoneBadge zone={4} />);

    expect(screen.getByText("Z4")).toHaveTextContent("Z4 Threshold");
  });
});

describe("WorkoutProfile", () => {
  test("draws one bar per step with repeats written out, and describes them", () => {
    const { container } = render(<WorkoutProfile steps={sessions.bike.structure.steps} />);

    const profile = screen.getByRole("img", {
      name: "Workout profile: 10′ warm-up in Z1, 10′ warm-up in Z2, 3 × (12′ work in Z4, 6′ recovery in Z1), 30′ work in Z2, 7′ cool-down",
    });
    expect(profile).toBeInTheDocument();
    expect(container.querySelectorAll("rect")).toHaveLength(2 + 3 * 2 + 2);
  });

  test("draws nothing for a session without steps", () => {
    const { container } = render(<WorkoutProfile steps={[]} />);

    expect(container).toBeEmptyDOMElement();
  });
});

describe("SessionChip", () => {
  test("marks a done or skipped session and colours an upcoming one by its sport", () => {
    render(
      <>
        <SessionChip session={sessions.swim} />
        <SessionChip session={sessions.strength} />
        <SessionChip session={sessions.bike} />
      </>,
    );

    expect(screen.getByText("Done:").parentElement).toHaveTextContent(
      "✓ Done: Swim — endurance 1h08",
    );
    expect(screen.getByText("Skipped:").parentElement).toHaveTextContent("Skipped: Strength 40′");
    expect(screen.getByText("Bike — threshold 3 × 12′ 1h45")).toHaveClass(
      "text-discipline-bike-soft",
    );
  });
});

describe("SessionRow", () => {
  test("links a session with its discipline, title, detail and state", () => {
    render(
      <SessionRow
        discipline="swim"
        title="Swim — endurance"
        detail="3.05 km · 1:08:40"
        state="done"
        linkProps={{ href: "/sessions/1" }}
      />,
    );

    const row = screen.getByRole("link", { name: /Swim — endurance/ });
    expect(row).toHaveAttribute("href", "/sessions/1");
    expect(within(row).getByRole("img", { name: "Swim" })).toBeInTheDocument();
    expect(row).toHaveTextContent("3.05 km · 1:08:40");
    expect(row).toHaveTextContent("✓ Done");
  });

  test("leaves out the detail and the state when there are none", () => {
    render(<SessionRow discipline="other" title="Walk" linkProps={{ href: "/activities/1" }} />);

    const row = screen.getByRole("link", { name: /^Other\s*Walk$/ });
    expect(row).not.toHaveAttribute("aria-current");
  });

  test("marks the row that is shown", () => {
    render(
      <SessionRow discipline="run" title="Run" selected linkProps={{ href: "/sessions/1" }} />,
    );

    expect(screen.getByRole("link", { name: /Run/ })).toHaveAttribute("aria-current", "true");
  });
});

describe("CoachNote", () => {
  test("shows the rationale under its label", () => {
    render(<CoachNote>{sessions.bike.rationale}</CoachNote>);

    expect(screen.getByText("Why this session")).toBeInTheDocument();
    expect(screen.getByText(/Each load cycle adds two minutes/)).toBeInTheDocument();
  });
});

describe("Button", () => {
  test("is a button that reports a press", async () => {
    let pressed = 0;
    render(
      <>
        <Button onClick={() => pressed++}>Sign in</Button>
        <Button variant="secondary">Upload</Button>
        <Button variant="quiet">Sign out</Button>
      </>,
    );

    await userEvent.click(screen.getByRole("button", { name: "Sign in" }));

    expect(pressed).toBe(1);
    expect(screen.getByRole("button", { name: "Sign in" })).toHaveAttribute("type", "button");
    expect(screen.getByRole("button", { name: "Upload" })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Sign out" })).toBeInTheDocument();
  });
});

describe("TextField", () => {
  test("labels its input and ties an error to it", async () => {
    render(<TextField label="Email" type="email" error="Enter your email" />);

    const input = screen.getByLabelText("Email");
    await userEvent.type(input, "ada@example.com");

    expect(input).toHaveValue("ada@example.com");
    expect(input).toBeInvalid();
    expect(input).toHaveAccessibleDescription("Enter your email");
  });

  test("is valid without an error", () => {
    render(<TextField label="Password" type="password" />);

    expect(screen.getByLabelText("Password")).toBeValid();
  });
});

describe("Frame", () => {
  test("puts the bar above the page's main landmark", () => {
    render(
      <Frame bar={<header>vire</header>}>
        <h1>Today</h1>
      </Frame>,
    );

    expect(screen.getByRole("banner")).toHaveTextContent("vire");
    expect(within(screen.getByRole("main")).getByRole("heading", { name: "Today" })).toBeVisible();
  });
});

describe("PageHeader", () => {
  test("titles the page under its label, with its line and figures", () => {
    render(
      <PageHeader label="Goal" title="Autumn 10 km" detail="Ten kilometres in December.">
        <Stat value={8} label="weeks to go" />
      </PageHeader>,
    );

    const header = screen.getByRole("banner");
    expect(within(header).getByRole("heading", { level: 1, name: "Autumn 10 km" })).toBeVisible();
    expect(header).toHaveTextContent("Goal");
    expect(header).toHaveTextContent("Ten kilometres in December.");
    expect(header).toHaveTextContent("8weeks to go");
  });
});

describe("Screen", () => {
  test("holds the page in a main landmark", () => {
    render(
      <Screen>
        <h1>Today</h1>
      </Screen>,
    );

    expect(within(screen.getByRole("main")).getByRole("heading", { name: "Today" })).toBeVisible();
  });
});
