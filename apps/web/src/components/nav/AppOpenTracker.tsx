"use client";

import { usePathname } from "next/navigation";
import { useEffect } from "react";

import { noteRoute } from "@/lib/app-open-landing";

/** W7 screen 12: tells the app-open landing when the person has moved on from the first screen. */
export function AppOpenTracker() {
  const pathname = usePathname();
  useEffect(() => {
    noteRoute(pathname);
  }, [pathname]);
  return null;
}
