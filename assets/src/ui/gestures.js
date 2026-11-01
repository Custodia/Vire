import { useEffect, useRef } from "react";

const SWIPE_PX = 60;
const SLIDE_PX = 10;
const SLIDE_ACTUATES = 0.25;
const CLICK_AFTER_MS = 400;

/**
 * Calls `onLeft` or `onRight` when a touch on the element at `ref` sweeps
 * that way, mostly sideways and at least 60 px. A sweep that starts inside a
 * scrolling row is left to the row.
 */
export function useSwipe(ref, { onLeft, onRight }) {
  const handlers = useRef({ onLeft, onRight });
  useEffect(() => {
    handlers.current = { onLeft, onRight };
  });

  useEffect(() => {
    const element = ref.current;
    if (!element) return undefined;
    let start = null;

    const begin = (event) => {
      const touch = event.touches[0];
      start =
        event.touches.length === 1 && !event.target.closest("[data-scrolls]")
          ? { x: touch.clientX, y: touch.clientY }
          : null;
    };
    const end = (event) => {
      if (!start) return;
      const touch = event.changedTouches[0];
      const dx = touch.clientX - start.x;
      const dy = touch.clientY - start.y;
      start = null;
      if (Math.abs(dx) < SWIPE_PX || Math.abs(dx) < 1.5 * Math.abs(dy)) return;
      (dx < 0 ? handlers.current.onLeft : handlers.current.onRight)?.();
    };

    element.addEventListener("touchstart", begin, { passive: true });
    element.addEventListener("touchend", end, { passive: true });
    return () => {
      element.removeEventListener("touchstart", begin);
      element.removeEventListener("touchend", end);
    };
  }, [ref]);
}

/**
 * Follows a touch that slides sideways along the element at `ref`, taken as
 * `parts` equal parts with the touch starting on part `from`. Calls `onSlide`
 * with where the slide has come to, as a fractional part, and `onLet` with the
 * part it is let go on: the next part over once it has come a quarter of the
 * way there. A touch that does not slide stays a tap, and the click a browser
 * may send at the end of a slide to another part is dropped.
 */
export function useSlide(ref, { parts, from, onSlide, onLet }) {
  const latest = useRef({ parts, from, onSlide, onLet });
  useEffect(() => {
    latest.current = { parts, from, onSlide, onLet };
  });

  useEffect(() => {
    const element = ref.current;
    let start = null;
    let position = null;
    let slidAt = -Infinity;

    const begin = (event) => {
      const touch = event.touches[0];
      start = event.touches.length === 1 ? { x: touch.clientX, y: touch.clientY } : null;
      position = null;
      slidAt = -Infinity;
    };
    const follow = (event) => {
      if (start == null) return;
      const touch = event.touches[0];
      const dx = touch.clientX - start.x;
      if (position == null) {
        if (Math.abs(dx) < SLIDE_PX) return;
        if (Math.abs(dx) < Math.abs(touch.clientY - start.y)) {
          start = null;
          return;
        }
      }
      if (event.cancelable) event.preventDefault();
      const { parts, from, onSlide } = latest.current;
      const width = element.clientWidth / parts || 1;
      position = Math.min(parts - 1, Math.max(0, from + dx / width));
      onSlide(position);
    };
    const end = () => {
      if (position != null) {
        const { from, onLet } = latest.current;
        const moved = position - from;
        const part = from + Math.sign(moved) * Math.ceil(Math.abs(moved) - SLIDE_ACTUATES);
        if (part !== from) slidAt = performance.now();
        onLet(part);
      }
      start = null;
      position = null;
    };
    const swallow = (event) => {
      if (performance.now() - slidAt > CLICK_AFTER_MS) return;
      slidAt = -Infinity;
      event.preventDefault();
      event.stopPropagation();
    };

    element.addEventListener("touchstart", begin, { passive: true });
    element.addEventListener("touchmove", follow, { passive: false });
    element.addEventListener("touchend", end, { passive: true });
    element.addEventListener("touchcancel", end, { passive: true });
    element.addEventListener("click", swallow, { capture: true });
    return () => {
      element.removeEventListener("touchstart", begin);
      element.removeEventListener("touchmove", follow);
      element.removeEventListener("touchend", end);
      element.removeEventListener("touchcancel", end);
      element.removeEventListener("click", swallow, { capture: true });
    };
  }, [ref]);
}
