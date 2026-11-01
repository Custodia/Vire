import { useRef, useState } from "react";
import { Dialog, Modal, ModalOverlay } from "react-aria-components";

const CLOSE_PX = 80;

/**
 * A dialog over the page: a sheet from the bottom edge on a phone, which a
 * drag down its handle closes, and a card in the middle on a desktop.
 * `children` is a function of `close`, as a react-aria Dialog takes it.
 */
export function Sheet({ isOpen, onOpenChange, label, className = "", children }) {
  const [dragged, setDragged] = useState(0);
  const start = useRef(null);

  const handle = {
    onPointerDown: (event) => {
      start.current = event.clientY;
      event.currentTarget.setPointerCapture?.(event.pointerId);
    },
    onPointerMove: (event) => {
      if (start.current != null) setDragged(Math.max(0, event.clientY - start.current));
    },
    onPointerUp: () => {
      if (dragged >= CLOSE_PX) onOpenChange(false);
      start.current = null;
      setDragged(0);
    },
  };

  return (
    <ModalOverlay
      isDismissable
      isOpen={isOpen}
      onOpenChange={onOpenChange}
      className="fixed inset-0 z-50 flex items-end justify-center bg-ground/80 lg:items-center"
    >
      <Modal
        className="w-full lg:max-w-md"
        style={dragged ? { transform: `translateY(${dragged}px)` } : undefined}
      >
        <Dialog
          aria-label={label}
          className={`flex flex-col gap-4 rounded-t-card border border-border bg-surface px-4 pt-2 pb-[max(1.5rem,env(safe-area-inset-bottom))] shadow-[0_20px_50px_rgba(0,0,0,0.55)] outline-none lg:rounded-card lg:p-5.5 ${className}`}
        >
          {(renderProps) => (
            <>
              <div
                aria-hidden="true"
                className="-mb-2 flex touch-none justify-center py-1.5 lg:hidden"
                {...handle}
              >
                <span className="h-1 w-10 rounded-pill bg-rule" />
              </div>
              {children(renderProps)}
            </>
          )}
        </Dialog>
      </Modal>
    </ModalOverlay>
  );
}
