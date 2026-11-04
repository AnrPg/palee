import { render, screen } from "@testing-library/react";
import { NextIntlClientProvider } from "next-intl";
import { describe, expect, it } from "vitest";

import el from "../../../messages/el.json";

import { certificateLine, DnsRecords, DomainStatusLine, isSystemHost } from "./DomainParts";

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

// ADR-398 (2026-11-03): what the cluster refuses, and what an apex adds.
describe("not available, system domains and apex records", () => {
  it("a host the cluster refused says so whatever the DNS state, except once expired", () => {
    const line = { key: "domains.certificateError.host_not_allowed", tone: "danger" };
    expect(certificateLine("pending_tls", "failed", "host_not_allowed")).toEqual(line);
    expect(certificateLine("pending_dns", "failed", "host_not_allowed")).toEqual(line);
    expect(certificateLine("active", "failed", "host_not_allowed")).toEqual(line);
    expect(certificateLine("expired", "failed", "host_not_allowed")).toBeNull();
  });

  it("tells the owner in plain Greek what to do", () => {
    wrap({ status: "pending_tls", lastError: "tls_not_ready", certificateStatus: "failed", certificateError: "host_not_allowed" });
    const text = screen.getByTestId("site-domain-certificate").textContent ?? "";
    expect(text).toContain("Αυτό το domain δεν είναι διαθέσιμο");
    expect(text).toContain("υποστήριξη");
  });

  it("knows the system domains, with or without what the owner pasted around them", () => {
    for (const host of ["palee.app", "box.palee.app", "milos.4kq.net", "x.milos.4kq.net", "ATHA.GR", "https://www.atha.io/", "atha.gr."]) {
      expect(isSystemHost(host)).toBe(true);
    }
    for (const host of ["www.mybox.gr", "notpalee.app", "atha.gr.example.com", "mybox.io"]) {
      expect(isSystemHost(host)).toBe(false);
    }
  });

  it("an apex record reads as CNAME flattening / ALIAS / ANAME, with why not a fixed A", () => {
    render(
      <NextIntlClientProvider locale="el" messages={el}>
        <DnsRecords records={[{ type: "ALIAS", name: "mybox.gr", value: "sites.palee.app" }]} />
      </NextIntlClientProvider>,
    );
    expect(screen.getByText(/CNAME \/ ALIAS \/ ANAME/)).toBeTruthy();
    expect(screen.getByTestId("site-dns-alias-hint").textContent).toContain("οι διευθύνσεις μας αλλάζουν");
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
