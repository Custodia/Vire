import { useState } from "react";
import { Outlet, useLocation } from "@tanstack/react-router";
import { LiveUpdates } from "../live/LiveUpdates.jsx";
import { Frame, PhoneFrame } from "../ui/Frame.jsx";
import { useIsDesktop } from "../ui/layout.js";
import { TabBar } from "../ui/TabBar.jsx";
import { ToastProvider } from "../ui/Toasts.jsx";
import { TopBar } from "../ui/TopBar.jsx";
import { MoreSheet } from "./more.jsx";
import { SignOutButton } from "./sign-out.jsx";
import { SyncButton, SyncStamp, SyncToasts } from "./sync.jsx";
import { UploadDialog, UploadSheet } from "./upload.jsx";

const screens = [
  {
    to: "/calendar",
    label: "Calendar",
    paths: ["/calendar", "/sessions", "/activities"],
    icon: (
      <>
        <rect x="3.5" y="5" width="17" height="15.5" rx="3" />
        <path d="M3.5 10h17M8 3v4M16 3v4" />
      </>
    ),
  },
  {
    to: "/plan",
    label: "Plan",
    paths: ["/plan"],
    icon: <path d="M4 6h9M4 12h16M4 18h11" strokeWidth="2.4" />,
  },
];

/**
 * Every signed-in screen inside one frame, which stays put as the screens
 * change, kept current by the user's live updates: a bar across the top on a
 * desktop and tabs along the bottom on a phone.
 */
export function AppFrame() {
  const desktop = useIsDesktop();
  const { pathname } = useLocation();
  const links = screens.map(({ paths, ...link }) => ({
    ...link,
    current: paths.some((path) => pathname.startsWith(path)),
  }));

  return (
    <ToastProvider>
      <LiveUpdates />
      <SyncToasts />
      {desktop ? (
        <Frame
          bar={
            <TopBar
              links={links}
              actions={
                <>
                  <SyncStamp />
                  <UploadDialog />
                  <SyncButton />
                  <SignOutButton />
                </>
              }
            />
          }
        >
          <Outlet />
        </Frame>
      ) : (
        <PhoneScreens links={links} />
      )}
    </ToastProvider>
  );
}

function PhoneScreens({ links }) {
  const [sheet, setSheet] = useState(null);
  const opener = (name) => (open) => setSheet(open ? name : null);

  return (
    <PhoneFrame
      tabs={<TabBar links={links} moreOpen={sheet === "more"} onMore={() => setSheet("more")} />}
    >
      <Outlet />
      <MoreSheet
        isOpen={sheet === "more"}
        onOpenChange={opener("more")}
        onUpload={() => setSheet("upload")}
      />
      <UploadSheet isOpen={sheet === "upload"} onOpenChange={opener("upload")} />
    </PhoneFrame>
  );
}
