"use client";

import Link from "next/link";
import { useRef, useState, type CSSProperties, type KeyboardEvent, type PointerEvent } from "react";

import type { PublicPackage } from "@/api/my-payments";
import { siteTextFor } from "@/lib/site-translations";

import { packagesInOrder } from "../site-data";
import { money, usePeriodLabel, useSite, useSiteText } from "../site-context";
import { usePreviewGuard } from "./social";

export type PackageView = { id: string; name: string; description: string; price: string; per: string; trial: boolean; raw: PublicPackage };

/** The packages in the page's language, the trial first. */
export function usePackages(): PackageView[] {
  const { packages, site, locale } = useSite();
  const { t } = useSiteText();
  const per = usePeriodLabel();
  return packagesInOrder(packages).map((pkg) => ({
    id: pkg.id,
    name: siteTextFor(site.texts, "package", pkg.id, "name", pkg.name),
    description: pkg.description ? siteTextFor(site.texts, "package", pkg.id, "description", pkg.description) : "",
    price: pkg.base_price_cents > 0 ? money(pkg.base_price_cents, pkg.currency, locale) : t("free"),
    per: per(pkg.billing_period, pkg.package_type),
    trial: pkg.package_type === "trial",
    raw: pkg,
  }));
}

/** The sales page of the app (sign-in, «Πριν πληρώσεις»), where buying happens (ADR-248). */
export function salesHref(slug: string, packageId = "all") {
  return `/b/${encodeURIComponent(slug)}/packages?buy=${encodeURIComponent(packageId)}`;
}

/**
 * A package's button: with the trial form, «Ξεκίνα με δοκιμαστικό» (the
 * package goes in the form); otherwise «Επίλεξε», which opens the app's
 * sales page.
 */
export function PackageAction({ pkg, className = "btn", style }: { pkg: PackageView; className?: string; style?: CSSProperties }) {
  const { on, act, site } = useSite();
  const { t } = useSiteText();
  const guard = usePreviewGuard();
  if (on("trial_form"))
    return (
      <button type="button" className={className} style={style} onClick={() => act(pkg.trial ? "" : pkg.name, "trial")}>
        {pkg.trial ? t("packages.bookTrial") : t("packages.startTrial")}
      </button>
    );
  return (
    <Link href={salesHref(site.slug, pkg.id)} className={className} style={style} onClick={guard} data-testid="site-package-choose">
      {t("packages.choose")}
    </Link>
  );
}

/** «Αγόρασε online»: the whole list on the app's sales page. */
export function BuyOnline() {
  const { site, onlinePayments } = useSite();
  const { t } = useSiteText();
  const guard = usePreviewGuard();
  if (!onlinePayments) return null;
  return (
    <p className="buyline">
      <Link href={salesHref(site.slug)} onClick={guard} data-testid="site-buy-online">
        {t("packages.buyOnline")} ↗
      </Link>
    </p>
  );
}

/** «Αρένα»: big prices on cards. */
export function PackageCardsA({ limit }: { limit?: number }) {
  const { t } = useSiteText();
  const list = usePackages();
  const shown = limit ? list.filter((pkg) => !pkg.trial).slice(0, limit) : list;
  return (
    <div className="priceA" data-testid="site-packages">
      {(shown.length ? shown : list.slice(0, limit)).map((pkg, index) => (
        <div key={pkg.id} className="pkg" data-rv="up" style={{ "--d": `${index * 110}ms` } as CSSProperties}>
          <b>{pkg.name}</b>
          <div className="p">{pkg.price}</div>
          {pkg.per ? <span className="muted">{pkg.per}</span> : null}
          <p className="desc">{pkg.description}</p>
          <PackageAction pkg={pkg} className={`btn ${index === 0 ? "" : "ghost"}`} style={{ width: "100%" }} />
        </div>
      ))}
      <span className="sr">{t("packages.title")}</span>
    </div>
  );
}

/** «Πλακίδια» and «Ιστορίες» inner pages: one tile per package. */
export function PackageTiles() {
  const list = usePackages();
  return (
    <div className="pkgcards" data-testid="site-packages">
      {list.map((pkg, index) => (
        <div key={pkg.id} className="tile pkgtile ld-pop" style={{ "--i": index } as CSSProperties}>
          <span className="k">{pkg.per}</span>
          <span className="v">{pkg.name}</span>
          <span className="price">{pkg.price}</span>
          {pkg.description ? (
            <span className="muted" style={{ fontSize: 14 }}>
              {pkg.description}
            </span>
          ) : null}
          <PackageAction pkg={pkg} />
        </div>
      ))}
    </div>
  );
}

/** «Ατελιέ»: a price list like a menu. */
export function PackageMenu() {
  const list = usePackages();
  return (
    <div className="menuList" data-testid="site-packages">
      {list.map((pkg, index) => (
        <div key={pkg.id} className="mi" data-rv="up" style={{ "--d": `${index * 70}ms` } as CSSProperties}>
          <div>
            <h3>{pkg.name}</h3>
            {pkg.description ? (
              <span className="muted" style={{ fontSize: 14 }}>
                {pkg.description}
              </span>
            ) : null}
          </div>
          <div className="p">
            {pkg.price}
            {pkg.per ? <small>{pkg.per}</small> : null}
          </div>
          <div className="act">
            <PackageAction pkg={pkg} className="linkD" />
          </div>
        </div>
      ))}
    </div>
  );
}

/**
 * «Ιστορίες»: a stack of cards. Swipe the top card sideways, or use the
 * arrow buttons or the arrow keys; the dots say where you are.
 */
export function PackageStack() {
  const { t } = useSiteText();
  const { calm } = useSite();
  const list = usePackages();
  const [index, setIndex] = useState(() => (list.length > 1 && list[0]?.trial ? 1 : 0));
  const drag = useRef<{ x: number; id: number } | null>(null);
  const [dx, setDx] = useState(0);
  if (list.length === 0) return null;
  const current = Math.min(index, list.length - 1);
  const move = (step: number) => setIndex((value) => Math.max(0, Math.min(list.length - 1, value + step)));

  function down(event: PointerEvent<HTMLDivElement>) {
    if ((event.target as Element).closest("button,a")) return;
    drag.current = { x: event.clientX, id: event.pointerId };
    event.currentTarget.setPointerCapture?.(event.pointerId);
  }
  function moveDrag(event: PointerEvent<HTMLDivElement>) {
    if (drag.current) setDx(event.clientX - drag.current.x);
  }
  function up() {
    if (!drag.current) return;
    drag.current = null;
    if (Math.abs(dx) > 60) move(dx < 0 ? 1 : -1);
    setDx(0);
  }
  function key(event: KeyboardEvent<HTMLDivElement>) {
    if (event.key === "ArrowRight") move(1);
    if (event.key === "ArrowLeft") move(-1);
  }

  return (
    <div data-testid="site-packages">
      <div
        className="stack"
        tabIndex={0}
        role="group"
        aria-roledescription={t("packages.carousel")}
        aria-label={t("packages.stackLabel")}
        onPointerDown={down}
        onPointerMove={moveDrag}
        onPointerUp={up}
        onPointerCancel={up}
        onKeyDown={key}
      >
        {list.map((pkg, position) => {
          const offset = position - current;
          const visible = offset >= 0 && offset < 3;
          const top = offset === 0;
          return (
            <div
              key={pkg.id}
              className={`pk ${top && dx ? "dragging" : ""}`}
              style={
                {
                  transform:
                    calm && !top
                      ? `translateY(${offset * 14}px)`
                      : top && dx
                        ? `translateX(${dx}px) rotate(${(dx / 20).toFixed(1)}deg)`
                        : `translateY(${offset * 14}px) scale(${1 - offset * 0.05})`,
                  opacity: visible ? 1 : 0,
                  "--k": Math.abs(offset),
                  pointerEvents: visible && top ? undefined : "none",
                } as CSSProperties
              }
              aria-hidden={!top}
              inert={!top}
            >
              <div>
                <span className="eyebrow">{pkg.per}</span>
                <h3>{pkg.name}</h3>
                {pkg.description ? <p className="muted" style={{ marginTop: 6 }}>{pkg.description}</p> : null}
              </div>
              <div className="row">
                <span className="p">{pkg.price}</span>
                <PackageAction pkg={pkg} />
              </div>
            </div>
          );
        })}
      </div>
      <div className="stackbar">
        <div className="carobtns">
          <button type="button" onClick={() => move(-1)} disabled={current === 0} aria-label={t("packages.prev")}>
            ←
          </button>
        </div>
        <div className="dots" aria-hidden="true">
          {list.map((pkg, position) => (
            <i key={pkg.id} className={position === current ? "on" : ""} />
          ))}
        </div>
        <span className="sr" aria-live="polite">
          {t("packages.position", { index: current + 1, count: list.length })}
        </span>
        <div className="carobtns">
          <button type="button" onClick={() => move(1)} disabled={current === list.length - 1} aria-label={t("packages.next")}>
            →
          </button>
        </div>
      </div>
    </div>
  );
}
