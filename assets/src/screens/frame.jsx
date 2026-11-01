import { useState } from "react";
import { Outlet, useLocation } from "@tanstack/react-router";
import { Frame, PhoneFrame } from "../ui/Frame.jsx";
import { useIsDesktop } from "../ui/layout.js";
import { TabBar } from "../ui/TabBar.jsx";
import { TopBar } from "../ui/TopBar.jsx";
import { MoreSheet } from "./more.jsx";
import { SignOutButton } from "./sign-out.jsx";

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
 * change: a bar across the top on a desktop and tabs along the bottom on a
 * phone.
 */
export function AppFrame() {
  const desktop = useIsDesktop();
  const { pathname } = useLocation();
  const links = screens.map(({ paths, ...link }) => ({
    ...link,
    current: paths.some((path) => pathname.startsWith(path)),
  }));

  return desktop ? (
    <Frame bar={<TopBar links={links} actions={<SignOutButton />} />}>
      <Outlet />
    </Frame>
  ) : (
    <PhoneScreens links={links} />
  );
}

function PhoneScreens({ links }) {
  const [more, setMore] = useState(false);

  return (
    <PhoneFrame tabs={<TabBar links={links} moreOpen={more} onMore={() => setMore(true)} />}>
      <Outlet />
      <MoreSheet isOpen={more} onOpenChange={setMore} />
    </PhoneFrame>
  );
}
