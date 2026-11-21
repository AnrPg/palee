"use client";

import { createContext, useContext, type ReactNode } from "react";

/**
 * ADR-680: what a new WOD started here is for. Inside a day, class, athlete
 * or member screen («+ Νέο WOD») the WOD is made for that one thing, so the
 * server moves it into that thing's library folder when it is assigned,
 * instead of leaving it at the library root with a copy in the folder.
 */
const MadeForAssignment = createContext(false);

export function NewWorkoutForAssignment({ children }: { children: ReactNode }) {
  return <MadeForAssignment.Provider value>{children}</MadeForAssignment.Provider>;
}

/** Whether a draft created here is made for one assignment (ADR-680). */
export function useNewWorkoutForAssignment() {
  return useContext(MadeForAssignment);
}
