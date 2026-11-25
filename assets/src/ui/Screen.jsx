/** The signed-out page shell: a narrow column on the ground colour, inside the safe area. */
export function Screen({ children }) {
  return (
    <div className="min-h-dvh bg-ground font-body text-ink">
      <main className="screen-insets mx-auto flex w-full max-w-xl flex-col gap-3.5">
        {children}
      </main>
    </div>
  );
}
