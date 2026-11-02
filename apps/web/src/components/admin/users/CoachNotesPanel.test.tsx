import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import type { ReactNode } from "react";
import { beforeEach, describe, expect, it, vi } from "vitest";

import { CoachNotesPanel } from "./CoachNotesPanel";

const createCoachNote = vi.fn();
const fetchCoachNotes = vi.fn();
let membership: { role: string; roles: string[]; capabilities: Record<string, boolean>; notes_visible_to_admins?: boolean } = {
  role: "coach",
  roles: ["coach"],
  capabilities: { write_coach_notes: true },
};

vi.mock("next-intl", () => ({
  useLocale: () => "en",
  useTranslations: () => (key: string) => key,
}));
vi.mock("@/i18n/ui", () => ({ useUiTranslations: () => (key: string) => key }));
vi.mock("@/i18n/use-ui-locale", () => ({ useUiLocale: () => "en" }));
vi.mock("@/components/session-provider", () => ({
  useSession: () => ({ tokens: { access_token: "tok" }, currentUser: { id: "me" } }),
}));
vi.mock("@/lib/membership-role", () => ({ useSelectedMembershipRole: () => ({ membership }) }));
vi.mock("@/api/roles", () => ({
  createCoachNote: (...args: unknown[]) => createCoachNote(...args),
  fetchCoachNotes: (...args: unknown[]) => fetchCoachNotes(...args),
  fetchCoachNoteReads: vi.fn(async () => []),
  deleteCoachNote: vi.fn(),
  updateCoachNote: vi.fn(),
  setNotesVisibility: vi.fn(),
}));

function renderPanel() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  const wrapper = ({ children }: { children: ReactNode }) => <QueryClientProvider client={client}>{children}</QueryClientProvider>;
  return render(<CoachNotesPanel userId="client-1" />, { wrapper });
}

const note = (id: string, audience: "private" | "staff" | null) => ({
  id,
  body: `note ${id}`,
  audience,
  coach_user_id: "someone",
  coach_nickname: "Coach",
  client_user_id: "client-1",
  inserted_at: null,
  updated_at: null,
  subject_kind: null,
  subject_id: null,
});

describe("CoachNotesPanel audience (ADR-359, mockup e5 A)", () => {
  beforeEach(() => {
    createCoachNote.mockReset();
    createCoachNote.mockResolvedValue({});
    fetchCoachNotes.mockReset();
    fetchCoachNotes.mockResolvedValue([note("n1", "staff"), note("n2", null)]);
    membership = { role: "coach", roles: ["coach"], capabilities: { write_coach_notes: true } };
  });

  it("marks who reads each note; an older note without one is private", async () => {
    renderPanel();
    expect(await screen.findByTestId("note-audience-staff")).toHaveTextContent("noteBadgeStaff");
    expect(screen.getByTestId("note-audience-private")).toHaveTextContent("noteBadgePrivate");
  });

  it("a coach starts from «Μόνο εγώ» and may share it with the staff", async () => {
    renderPanel();
    expect(await screen.findByRole("radio", { name: "noteAudiencePrivate" })).toBeChecked();
    fireEvent.click(screen.getByRole("radio", { name: "noteAudienceStaff" }));
    expect(screen.getByText("noteStaffHint")).toBeInTheDocument();
    fireEvent.change(screen.getByRole("textbox", { name: "rhNewNote" }), { target: { value: "Knee: no box jumps" } });
    fireEvent.click(screen.getByRole("button", { name: "rhAddNote" }));
    await waitFor(() => expect(createCoachNote).toHaveBeenCalledWith("tok", "client-1", "Knee: no box jumps", null, "staff"));
  });

  it("the front desk writes for the staff only, with no choice to make", async () => {
    membership = { role: "front_desk", roles: ["front_desk"], capabilities: { view_directory: true } };
    renderPanel();
    expect(await screen.findByText("noteStaffOnly")).toBeInTheDocument();
    expect(screen.queryByRole("radiogroup")).toBeNull();
    fireEvent.change(screen.getByRole("textbox", { name: "rhNewNote" }), { target: { value: "Paid cash" } });
    fireEvent.click(screen.getByRole("button", { name: "rhAddNote" }));
    await waitFor(() => expect(createCoachNote).toHaveBeenCalledWith("tok", "client-1", "Paid cash", null, "staff"));
  });
});
