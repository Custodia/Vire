import { useEffect, useRef, useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { getRouteApi, Link, useNavigate } from "@tanstack/react-router";
import { daysQuery, seasonQuery } from "../api/queries.js";
import { dayOf, shiftDate, viewPeriod, views } from "../lib/calendar.js";
import { isIsoDate, localDate } from "../lib/format.js";
import { calendarLink, rememberCalendarView } from "../lib/links.js";
import { weeksTo } from "../lib/plan.js";
import { buttonClass } from "../ui/Button.jsx";
import { useSlide } from "../ui/gestures.js";
import { useIsDesktop } from "../ui/layout.js";
import { Pager } from "../ui/Pager.jsx";
import { Stat } from "../ui/Stat.jsx";
import { aboveTabs } from "../ui/TabBar.jsx";
import { DesktopDay, PhoneDay } from "./calendar-day.jsx";
import { DesktopMonth, PhoneMonth } from "./calendar-month.jsx";
import { DesktopWeek, PhoneWeek } from "./calendar-week.jsx";
import { QueryContent } from "./query-content.jsx";

const route = getRouteApi("/authenticated/calendar/$view/$date");

const screens = {
  month: { desktop: DesktopMonth, phone: PhoneMonth },
  week: { desktop: DesktopWeek, phone: PhoneWeek },
  day: { desktop: DesktopDay, phone: PhoneDay },
};

const nouns = { month: "month", week: "week", day: "day" };
const chevrons = { previous: "M15 6l-6 6 6 6", next: "M9 6l6 6-6 6" };

/** The calendar: a month, a week or a day around the date in the URL. */
export function CalendarScreen() {
  const { view, date } = route.useParams();
  if (!views.includes(view)) return <NotFound />;
  if (!isIsoDate(date)) return <NotADate value={date} />;
  return <Calendar view={view} date={date} />;
}

/**
 * A view of the calendar with the days it shows, each drawn as of today, and
 * the season the first of them in the plan belongs to. `selected` is the
 * session or activity the desktop day shows. On a phone a sideways drag pulls
 * in the period before or after.
 */
export function Calendar({ view, date, selected }) {
  const desktop = useIsDesktop();
  const navigate = useNavigate();
  const around = (steps) => shiftDate(view, date, steps);
  usePrefetchAround(view, date);
  useEffect(() => rememberCalendarView(view), [view]);

  return desktop ? (
    <Period view={view} date={date} selected={selected} />
  ) : (
    <>
      <Pager
        pages={{ previous: around(-1), current: date, next: around(1) }}
        onStep={(steps) => navigate(calendarLink(view, around(steps)))}
        render={(each) => <Period view={view} date={each} />}
      />
      <PhoneViewBar view={view} date={date} />
    </>
  );
}

function Period({ view, date, selected }) {
  const today = localDate();
  const desktop = useIsDesktop();
  const period = viewPeriod(view, date);
  const query = useQuery(daysQuery(period.first, period.last));
  const days = query.data?.map((answer) => dayOf(answer, today));
  const chain = days?.map((day) => day.day?.chain).find(Boolean);
  const season = useQuery(seasonQuery(chain?.season.id ?? null)).data ?? null;

  const Screen = screens[view][desktop ? "desktop" : "phone"];
  const props = { view, date, today, season, selected };

  return (
    <QueryContent query={query} noun={nouns[view]}>
      {() => <Screen {...props} days={days} />}
    </QueryContent>
  );
}

function usePrefetchAround(view, date) {
  const queryClient = useQueryClient();

  useEffect(() => {
    for (const steps of [-1, 1]) {
      const { first, last } = viewPeriod(view, shiftDate(view, date, steps));
      queryClient.prefetchQuery(daysQuery(first, last));
    }
  }, [queryClient, view, date]);
}

/** The phone's calendar page: where its dates sit in the plan over its title, then its content. */
export function PhonePage({ label, title, header, children }) {
  return (
    <div className="flex min-h-[calc(100dvh-4.5rem)] flex-col">
      <header className="flex flex-col gap-3 border-b border-divider px-4 pt-[max(0.875rem,env(safe-area-inset-top))] pb-2.5">
        <div className="flex min-w-0 flex-col gap-0.5">
          {label && (
            <span className="truncate text-label font-semibold text-ink-muted uppercase">
              {label}
            </span>
          )}
          <h1 className="m-0 truncate text-[26px] font-bold tracking-tight">{title}</h1>
        </div>
        {header}
      </header>
      <main className="flex flex-col gap-3.5 px-4 pt-3.5 pb-21">{children}</main>
    </div>
  );
}

/** The phone calendar's view switch, held above the tabs in reach of a thumb. */
function PhoneViewBar({ view, date }) {
  return (
    <div className={`fixed inset-x-0 z-20 bg-ground ${aboveTabs}`}>
      <div className="mx-auto max-w-xl px-4 py-2">
        <ViewSwitch view={view} date={date} today={localDate()} />
      </div>
    </div>
  );
}

/** The desktop calendar's bar: back and on a period, Today, and the view switch. */
export function DesktopToolbar({ view, date, today }) {
  return (
    <div className="flex flex-wrap items-center gap-2">
      <StepLink view={view} date={date} direction="previous" />
      <StepLink view={view} date={date} direction="next" />
      <TodayLink view={view} date={date} today={today} />
      <span className="flex-1" />
      <ViewSwitch view={view} date={date} today={today} className="w-80" />
    </div>
  );
}

const periods = { month: "month", week: "week", day: "day" };

function StepLink({ view, date, direction }) {
  const steps = direction === "previous" ? -1 : 1;

  return (
    <Link
      {...calendarLink(view, shiftDate(view, date, steps))}
      aria-label={`${direction === "previous" ? "Previous" : "Next"} ${periods[view]}`}
      className="focus-ring grid size-11 flex-none place-items-center rounded-tile border border-border bg-surface text-ink-soft hover:bg-surface-raised"
    >
      <svg
        aria-hidden="true"
        width="18"
        height="18"
        viewBox="0 0 24 24"
        fill="none"
        stroke="currentColor"
        strokeWidth="2"
        strokeLinecap="round"
        strokeLinejoin="round"
      >
        <path d={chevrons[direction]} />
      </svg>
    </Link>
  );
}

function TodayLink({ view, date, today }) {
  const shown = date === today;

  return (
    <Link
      {...calendarLink(view, today)}
      aria-disabled={shown || undefined}
      className={buttonClass("secondary", shown ? "pointer-events-none text-ink-muted" : "")}
    >
      Today
    </Link>
  );
}

const viewLabels = { month: "Month", week: "Week", day: "Day" };

/**
 * Month, Week and Day over the date shown. The view shown leads to today, and
 * a finger sliding along the switch carries the selection to another view.
 */
function ViewSwitch({ view, date, today, className = "" }) {
  const nav = useRef(null);
  const navigate = useNavigate();
  const [slide, setSlide] = useState(null);
  const [shown, setShown] = useState(view);
  if (shown !== view) {
    setShown(view);
    setSlide(null);
  }
  const at = views.indexOf(view);
  const position = slide?.position ?? at;
  useSlide(nav, {
    parts: views.length,
    from: at,
    onSlide: (to) => setSlide({ position: to, moving: true }),
    onLet: (index) => {
      setSlide(index === at ? null : { position: index, moving: false });
      if (index !== at) navigate(calendarLink(views[index], date));
    },
  });

  return (
    <nav
      ref={nav}
      aria-label="Calendar view"
      className={`relative grid touch-pan-y grid-cols-3 gap-0.5 rounded-[13px] border border-border bg-surface p-0.75 ${className}`}
    >
      <span
        aria-hidden="true"
        className={`absolute inset-y-0.75 left-0.75 w-[calc((100%-0.625rem)/3)] rounded-[10px] bg-segment-selected ${
          slide?.moving ? "" : "transition-transform duration-200 ease-out"
        }`}
        style={{ transform: `translateX(calc(${position} * (100% + 2px)))` }}
      />
      {views.map((each, index) => (
        <Link
          key={each}
          {...calendarLink(each, each === view ? today : date)}
          aria-current={each === view ? "page" : undefined}
          className={`focus-ring relative grid min-h-9 place-items-center rounded-[10px] text-sm font-semibold no-underline ${
            index === Math.round(position) ? "text-ink" : "text-ink-muted hover:text-ink"
          }`}
        >
          {viewLabels[each]}
        </Link>
      ))}
    </nav>
  );
}

/** A desktop calendar heading: where the dates sit in the plan over the title, and the figures. */
export function DesktopHeading({ label, title, children }) {
  return (
    <section className="flex flex-wrap items-end justify-between gap-x-10 gap-y-5">
      <div className="flex min-w-0 flex-col gap-1.5">
        {label && (
          <span className="text-label font-semibold text-ink-muted uppercase">{label}</span>
        )}
        <h1 className="m-0 text-4xl font-bold tracking-tight">{title}</h1>
      </div>
      <div className="flex flex-wrap gap-7">{children}</div>
    </section>
  );
}

/** The weeks from today to the end of the season, as a figure. */
export function WeeksToGo({ season, today }) {
  return (
    season && (
      <Stat
        value={weeksTo(today, season.period.last)}
        label={`weeks to ${season.name}`}
        tone="accent"
      />
    )
  );
}

function NotFound() {
  return (
    <div className="flex flex-col gap-2 p-4 lg:p-0">
      <h1 className="m-0 text-3xl font-bold tracking-tight">Not found</h1>
      <p className="m-0 text-sm text-ink-soft">The calendar shows a month, a week or a day.</p>
    </div>
  );
}

function NotADate({ value }) {
  return (
    <div className="flex flex-col gap-2 p-4 lg:p-0">
      <h1 className="m-0 text-3xl font-bold tracking-tight">Not a date</h1>
      <p className="m-0 text-sm text-ink-soft">
        “{value}” is not a date written as year, month and day, such as 2026-11-03.
      </p>
    </div>
  );
}
