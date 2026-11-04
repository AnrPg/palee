"use client";

import React, { createContext, useContext, type ReactNode } from "react";

// ANR 2026-11-04 (mockups, help B): «?» on the class timer's remote shows a
// short caption under every control explaining what it does.

/** Whether the remote's «?» captions are showing. */
export const RemoteHelpContext = createContext(false);

export function useRemoteHelp() {
  return useContext(RemoteHelpContext);
}

/** A caption under a control, shown while «?» is on. */
export function HelpCaption({ children, id }: { children: ReactNode; id?: string }) {
  const on = useRemoteHelp();
  if (!on) return null;
  return (
    <span id={id} data-testid="remote-help" className="mt-0.5 block text-xs font-medium leading-snug" style={{ opacity: 0.8 }}>
      {children}
    </span>
  );
}
