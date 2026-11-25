import { createContext, useCallback, useContext, useEffect, useMemo, useState } from "react";
import { Toast } from "./Toast.jsx";

const ToastContext = createContext(null);

/**
 * Holds the toasts any screen shows, in a labelled region over the top of the
 * page, at its right on a desktop. `show` adds a toast or replaces the one
 * with the same id, and `dismiss` takes one away.
 */
export function ToastProvider({ children }) {
  const [toasts, setToasts] = useState([]);

  const dismiss = useCallback(
    (id) => setToasts((shown) => shown.filter((toast) => toast.id !== id)),
    [],
  );

  const show = useCallback(
    (toast) =>
      setToasts((shown) => {
        const index = shown.findIndex(({ id }) => id === toast.id);
        return index === -1 ? [...shown, toast] : shown.with(index, toast);
      }),
    [],
  );

  const value = useMemo(() => ({ show, dismiss }), [show, dismiss]);

  return (
    <ToastContext.Provider value={value}>
      {children}
      <section
        aria-label="Notifications"
        className="fixed inset-x-3 top-[max(0.75rem,env(safe-area-inset-top))] z-40 flex flex-col gap-2.5 empty:hidden lg:inset-x-auto lg:top-21 lg:right-8 lg:w-95"
      >
        {toasts.map((toast) => (
          <TimedToast key={toast.id} toast={toast} onDismiss={dismiss} />
        ))}
      </section>
    </ToastContext.Provider>
  );
}

/** The `show` and `dismiss` of the toasts around the caller. */
export function useToasts() {
  return useContext(ToastContext);
}

// A toast with a timeout hides itself once that many milliseconds pass without
// the pointer or the focus on it; showing it again starts the wait anew.
function TimedToast({ toast, onDismiss }) {
  const [held, setHeld] = useState(false);
  const { id, timeout, tone, title, body } = toast;

  useEffect(() => {
    if (!timeout || held) return undefined;
    const timer = setTimeout(() => onDismiss(id), timeout);
    return () => clearTimeout(timer);
  }, [toast, id, timeout, held, onDismiss]);

  return (
    <Toast
      tone={tone}
      title={title}
      onHide={() => onDismiss(id)}
      onPointerEnter={() => setHeld(true)}
      onPointerLeave={() => setHeld(false)}
      onFocus={() => setHeld(true)}
      onBlur={(event) => {
        if (!event.currentTarget.contains(event.relatedTarget)) setHeld(false);
      }}
    >
      {body}
    </Toast>
  );
}
