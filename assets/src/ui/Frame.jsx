/** The signed-in page shell on a desktop: the bar across the top and a board-wide page under it. */
export function Frame({ bar, children }) {
  return (
    <div className="min-h-dvh bg-ground font-body text-ink">
      {bar}
      <main className="mx-auto flex w-full max-w-board flex-col gap-5 px-8 pt-5 pb-12">
        {children}
      </main>
    </div>
  );
}

/** The signed-in page shell on a phone: the screen, with the tab bar fixed along the bottom. */
export function PhoneFrame({ tabs, children }) {
  return (
    <div className="min-h-dvh bg-ground font-body text-ink">
      <div className="mx-auto w-full max-w-xl pb-[calc(4.5rem+env(safe-area-inset-bottom))]">
        {children}
      </div>
      {tabs}
    </div>
  );
}
