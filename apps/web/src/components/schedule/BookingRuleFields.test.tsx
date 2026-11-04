import { fireEvent, render, screen } from "@testing-library/react";
import { useState } from "react";
import { describe, expect, it, vi } from "vitest";

import { ApprovalRuleFields } from "./BookingRuleFields";

vi.mock("next-intl", () => ({
  useTranslations: () => (key: string) => key,
}));

function Harness({ autoApprove, timeout }: { autoApprove: boolean; timeout: number | null }) {
  const [state, setState] = useState({ autoApprove, timeout });
  return (
    <>
      <ApprovalRuleFields
        testId="slot"
        autoApprove={state.autoApprove}
        onAutoApproveChange={(value) => setState((current) => ({ ...current, autoApprove: value }))}
        timeout={state.timeout}
        onTimeoutChange={(value) => setState((current) => ({ ...current, timeout: value }))}
      />
      <output data-testid="timeout">{String(state.timeout)}</output>
    </>
  );
}

describe("ApprovalRuleFields", () => {
  it("puts the automatic confirmation first and hides the approval wait while it is on", () => {
    render(<Harness autoApprove timeout={90} />);

    const rules = screen.getByTestId("slot-rules");
    expect(rules.firstElementChild).toContainElement(screen.getByTestId("slot-auto-approve"));
    expect(screen.getByTestId("slot-auto-approve")).toBeChecked();
    expect(screen.queryByTestId("slot-approval-wait")).toBeNull();
    expect(screen.getByText("autoApproveHelp")).toBeInTheDocument();
  });

  it("shows the wait once bookings need approval and keeps the saved time", () => {
    render(<Harness autoApprove timeout={90} />);

    fireEvent.click(screen.getByTestId("slot-auto-approve"));

    expect(screen.getByTestId("slot-approval-wait-hours")).toHaveValue(1);
    expect(screen.getByTestId("slot-approval-wait-minutes")).toHaveValue(30);
    expect(screen.getByText("approvalWaitClassHelp")).toBeInTheDocument();
    expect(screen.getByTestId("timeout")).toHaveTextContent("90");
  });

  it("lets a request wait until the class starts", () => {
    render(<Harness autoApprove={false} timeout={60} />);

    fireEvent.click(screen.getByTestId("slot-approval-wait-no-limit"));

    expect(screen.getByTestId("timeout")).toHaveTextContent("null");
    expect(screen.getByTestId("slot-approval-wait-hours")).toBeDisabled();
  });
});
