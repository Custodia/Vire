import { useEffect, useLayoutEffect, useRef, useState } from "react";

const LOCK_PX = 10;
const COMMIT_SHARE = 0.25;
const FLICK_PX_PER_MS = 0.4;
const SETTLE_MS = 220;

/**
 * Pages in a row that a sideways drag pulls along under the finger, the page
 * on either side coming in as it goes. Let go far or fast enough, the row
 * carries on to that page and `onStep` is called with 1 for the next page or
 * -1 for the previous one; otherwise it springs back. A drag that starts
 * inside a scrolling row is left to the row.
 *
 * `pages` keys the pages as `{ previous, current, next }` and `render` draws
 * the page for a key.
 */
export function Pager({ pages, onStep, render }) {
  const { previous, current, next } = pages;
  const track = useRef(null);
  const latest = useRef({ onStep, current });
  const [peek, setPeek] = useState(null);
  useEffect(() => {
    latest.current = { onStep, current };
  });

  useLayoutEffect(() => {
    track.current.style.transition = "";
    track.current.style.transform = "";
  }, [current]);

  useEffect(() => {
    const element = track.current;
    let drag = null;
    let settling = null;

    const begin = (event) => {
      const touch = event.touches[0];
      drag =
        !settling && event.touches.length === 1 && !event.target.closest("[data-scrolls]")
          ? { x: touch.clientX, y: touch.clientY, dx: 0, at: event.timeStamp, speed: 0 }
          : null;
    };
    const follow = (event) => {
      if (!drag) return;
      const touch = event.touches[0];
      const dx = touch.clientX - drag.x;
      const dy = touch.clientY - drag.y;
      if (!drag.axis) {
        if (Math.max(Math.abs(dx), Math.abs(dy)) < LOCK_PX) return;
        drag.axis = Math.abs(dx) > Math.abs(dy) ? "x" : "y";
        if (drag.axis === "x") {
          element.style.transition = "";
          setPeek({ at: latest.current.current, top: window.scrollY });
        }
      }
      if (drag.axis !== "x") return;
      if (event.cancelable) event.preventDefault();
      drag.speed = (dx - drag.dx) / Math.max(1, event.timeStamp - drag.at);
      drag.dx = dx;
      drag.at = event.timeStamp;
      element.style.transform = `translate3d(${dx}px, 0, 0)`;
    };
    const end = () => {
      if (drag?.axis !== "x") {
        drag = null;
        return;
      }
      const { dx, speed } = drag;
      drag = null;
      const flicked = Math.abs(speed) > FLICK_PX_PER_MS && Math.sign(speed) === Math.sign(dx);
      const steps =
        Math.abs(dx) > element.offsetWidth * COMMIT_SHARE || flicked ? -Math.sign(dx) : 0;
      const still = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
      element.style.transition = still ? "" : `transform ${SETTLE_MS}ms ease-out`;
      element.style.transform = `translate3d(${-steps * 100}%, 0, 0)`;
      settling = setTimeout(
        () => {
          settling = null;
          if (steps) latest.current.onStep(steps);
        },
        still ? 0 : SETTLE_MS,
      );
    };

    element.addEventListener("touchstart", begin, { passive: true });
    element.addEventListener("touchmove", follow, { passive: false });
    element.addEventListener("touchend", end, { passive: true });
    element.addEventListener("touchcancel", end, { passive: true });
    return () => {
      clearTimeout(settling);
      element.removeEventListener("touchstart", begin);
      element.removeEventListener("touchmove", follow);
      element.removeEventListener("touchend", end);
      element.removeEventListener("touchcancel", end);
    };
  }, []);

  const peeking = peek?.at === current;
  const shown = [
    peeking && { key: previous, side: "right-full" },
    { key: current },
    peeking && { key: next, side: "left-full" },
  ].filter(Boolean);

  return (
    <div className="overflow-clip">
      <div ref={track} className="relative touch-pan-y">
        {shown.map(({ key, side }) =>
          side ? (
            <div
              key={key}
              aria-hidden="true"
              inert
              className={`absolute ${side} w-full`}
              style={{ top: peek.top }}
            >
              {render(key)}
            </div>
          ) : (
            <div key={key}>{render(key)}</div>
          ),
        )}
      </div>
    </div>
  );
}
