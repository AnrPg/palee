import { render, screen } from "@testing-library/react";
import { NextIntlClientProvider } from "next-intl";
import { describe, expect, it } from "vitest";

import el from "../../../messages/el.json";

import { certificateLine, DomainStatusLine } from "./DomainParts";

function wrap(props: Parameters<typeof DomainStatusLine>[0]) {
  return render(
    <NextIntlClientProvider locale="el" messages={el}>
      <DomainStatusLine {...props} />
    </NextIntlClientProvider>,
  );
}

// ADR-398: the domain card's one line on the certificate Palee asks cert-manager for.
describe("certificateLine", () => {
  it("says nothing before DNS is proven or when Palee does not create certificates", () => {
    expect(certificateLine("pending_dns", "none", null)).toBeNull();
    expect(certificateLine("pending_tls", "none", null)).toBeNull();
    expect(certificateLine("pending_tls", undefined, undefined)).toBeNull();
    expect(certificateLine("expired", "failed", "cluster_refused")).toBeNull();
  });

  it("follows the certificate while the domain waits for it", () => {
    expect(certificateLine("pending_tls", "pending", null)?.key).toBe("domains.certificate.pending");
    expect(certificateLine("pending_tls", "issuing", null)?.key).toBe("domains.certificate.issuing");
    expect(certificateLine("pending_tls", "active", null)?.key).toBe("domains.certificate.active");
    expect(certificateLine("pending_tls", "pending", "cluster_unreachable")).toEqual({ key: "domains.certificateError.cluster_unreachable", tone: "warning" });
  });

  it("an active domain shows only a failure; unknown reasons read as a plain failure", () => {
    expect(certificateLine("active", "active", null)).toBeNull();
    expect(certificateLine("active", "failed", "rate_limited")).toEqual({ key: "domains.certificateError.rate_limited", tone: "danger" });
    expect(certificateLine("broken", "failed", "something_new")?.key).toBe("domains.certificateError.issuance_failed");
  });
});

describe("DomainStatusLine", () => {
  it("replaces the generic TLS reason with the certificate's state", () => {
    wrap({ status: "pending_tls", lastError: "tls_not_ready", certificateStatus: "issuing", certificateError: null });
    expect(screen.getByText("Περιμένει πιστοποιητικό")).toBeTruthy();
    expect(screen.getByTestId("site-domain-certificate").textContent).toBe("Το πιστοποιητικό εκδίδεται. Συνήθως θέλει λίγα λεπτά.");
    expect(screen.queryByText("Το πιστοποιητικό εκδίδεται.")).toBeNull();
  });

  it("gives a plain reason when the certificate failed", () => {
    wrap({ status: "pending_tls", lastError: "tls_not_ready", certificateStatus: "failed", certificateError: "challenge_failed" });
    expect(screen.getByTestId("site-domain-certificate").textContent).toContain("η Let's Encrypt δεν έφτασε στο domain");
  });

  it("keeps the earlier lines when Palee does not create certificates", () => {
    wrap({ status: "pending_tls", lastError: "tls_not_ready" });
    expect(screen.getByText("Το πιστοποιητικό εκδίδεται.")).toBeTruthy();
    expect(screen.queryByTestId("site-domain-certificate")).toBeNull();
  });
});
