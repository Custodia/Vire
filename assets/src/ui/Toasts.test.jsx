import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { useEffect } from "react";
import { act, fireEvent, render, screen } from "@testing-library/react";
import { ToastProvider, useToasts } from "./Toasts.jsx";

let toasts;

function Capture({ onToasts }) {
  const value = useToasts();
  useEffect(() => onToasts(value), [onToasts, value]);
  return null;
}

function renderToasts() {
  render(
    <ToastProvider>
      <Capture
        onToasts={(value) => {
          toasts = value;
        }}
      />
    </ToastProvider>,
  );
}

const show = (toast) => act(() => toasts.show({ tone: "success", title: "Synced", ...toast }));

describe("toasts", () => {
  beforeEach(() => vi.useFakeTimers());
  afterEach(() => vi.useRealTimers());

  test("hide themselves once their timeout passes", () => {
    renderToasts();
    show({ id: "a", timeout: 5000 });

    act(() => vi.advanceTimersByTime(4999));
    expect(screen.getByRole("status")).toHaveTextContent("Synced");

    act(() => vi.advanceTimersByTime(1));
    expect(screen.queryByRole("status")).toBeNull();
  });

  test("stay while the pointer or the focus is on them", () => {
    renderToasts();
    show({ id: "a", timeout: 5000 });
    const toast = screen.getByRole("status");

    fireEvent.pointerEnter(toast);
    act(() => vi.advanceTimersByTime(10_000));
    expect(screen.getByRole("status")).toBeInTheDocument();

    fireEvent.pointerLeave(toast);
    fireEvent.focus(screen.getByRole("button", { name: "Hide" }));
    act(() => vi.advanceTimersByTime(10_000));
    expect(screen.getByRole("status")).toBeInTheDocument();

    fireEvent.blur(screen.getByRole("button", { name: "Hide" }));
    act(() => vi.advanceTimersByTime(5000));
    expect(screen.queryByRole("status")).toBeNull();
  });

  test("without a timeout stay until hidden", () => {
    renderToasts();
    show({ id: "a", tone: "caution", title: "Paused" });

    act(() => vi.advanceTimersByTime(60_000));
    expect(screen.getByRole("alert")).toHaveTextContent("Paused");

    fireEvent.click(screen.getByRole("button", { name: "Hide" }));
    expect(screen.queryByRole("alert")).toBeNull();
  });

  test("are replaced in place by a toast with the same id", () => {
    renderToasts();
    show({ id: "a", tone: "busy", title: "Syncing" });
    show({ id: "b", tone: "caution", title: "Paused" });
    show({ id: "a", title: "Synced" });

    const region = screen.getByRole("region", { name: "Notifications" });
    expect(region.children).toHaveLength(2);
    expect(region.children[0]).toHaveTextContent("Synced");
    expect(region.children[1]).toHaveTextContent("Paused");
  });

  test("are taken away by dismiss", () => {
    renderToasts();
    show({ id: "a" });

    act(() => toasts.dismiss("a"));

    expect(screen.queryByRole("status")).toBeNull();
  });
});
