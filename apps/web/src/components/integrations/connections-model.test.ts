import { describe, expect, it } from "vitest";

import {
  PURPOSE_SCOPES,
  deliveryState,
  deliveryStatusParam,
  integrationErrorKey,
  scopesOf,
  shortUrl,
  toggleScope,
  webhookHealth,
  webhookUrlError,
} from "./connections-model";

describe("connections model (W10 screens 1–3)", () => {
  it("gives each purpose the fewest scopes it needs", () => {
    expect(PURPOSE_SCOPES.website).toEqual(["classes:read"]);
    expect(PURPOSE_SCOPES.zapier).toContain("webhooks:write");
    expect(PURPOSE_SCOPES.zapier).not.toContain("members:write");
  });

  it("offers payments as read only and toggles scopes in order", () => {
    expect(scopesOf("payments")).toEqual(["payments:read"]);
    expect(toggleScope(["members:read"], "classes:read")).toEqual(["classes:read", "members:read"]);
    expect(toggleScope(["classes:read", "members:read"], "classes:read")).toEqual(["members:read"]);
  });

  it("reads a webhook's health for the list badge", () => {
    const base = { status: "active" as const, consecutive_failures: 0, last_success_at: null, last_failure_at: null };
    expect(webhookHealth(base)).toBe("ok");
    expect(webhookHealth({ ...base, status: "disabled" })).toBe("off");
    expect(webhookHealth({ ...base, consecutive_failures: 2 })).toBe("failing");
    expect(webhookHealth({ ...base, last_success_at: "2026-11-03T07:00:00Z", last_failure_at: "2026-11-03T08:00:00Z" })).toBe("failing");
    expect(webhookHealth({ ...base, last_success_at: "2026-11-03T09:00:00Z", last_failure_at: "2026-11-03T08:00:00Z" })).toBe("ok");
  });

  it("names delivery states and maps the log's chips to the API", () => {
    expect(deliveryState({ status: "succeeded" })).toBe("delivered");
    expect(deliveryState({ status: "pending" })).toBe("retrying");
    expect(deliveryState({ status: "failed" })).toBe("failed");
    expect(deliveryStatusParam("all")).toBeUndefined();
    expect(deliveryStatusParam("failed")).toBe("failed");
  });

  it("checks a receiver's address before sending it", () => {
    expect(webhookUrlError(" ")).toBe("required");
    expect(webhookUrlError("http://example.com/hook")).toBe("https");
    expect(webhookUrlError("not a url")).toBe("https");
    expect(webhookUrlError("https://hooks.zapier.com/hooks/catch/1/8812")).toBeNull();
    expect(shortUrl("https://hooks.zapier.com/hooks/catch/1/8812")).toBe("hooks.zapier.com/…/8812");
    expect(shortUrl("https://crm.example.gr/")).toBe("crm.example.gr");
  });

  it("has a sentence for known API codes and a generic one otherwise", () => {
    expect(integrationErrorKey("blocked_address")).toBe("errors.blocked_address");
    expect(integrationErrorKey("door_offline")).toBe("errors.door_offline");
    expect(integrationErrorKey("something_new")).toBe("errors.generic");
    expect(integrationErrorKey(undefined)).toBe("errors.generic");
  });
});
