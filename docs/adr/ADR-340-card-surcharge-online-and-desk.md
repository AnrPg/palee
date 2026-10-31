# ADR-340: Card surcharge for online and desk card payments, within the law of the box's country
Date: 2026-10-31
Status: Accepted

## Context
ADR-264 records a card surcharge that the Viva.com Terminal app adds on Tap
to Pay. The product owner asked (CP-A5) for the same optional surcharge on
member online payments (checkout and saved cards, including autopay) and on
desk card payments taken on the box's own card machine (`card_manual`),
as a per-box setting, shown before paying, on the fiscal receipt as
revenue, and refused where it is illegal.

The law differs by country (read 2026-10-31):

- **EU/EEA**: PSD2 art. 62(4) (Directive 2015/2366) forbids surcharging
  payment instruments whose interchange is capped by the IFR (Regulation
  2015/751): consumer debit and credit cards issued in the EEA. Business
  (commercial) cards and cards issued outside the EEA may be surcharged,
  no higher than the direct cost to the merchant (art. 62(3)); a member
  state may ban or limit it further (art. 62(5)).
- **United Kingdom**: The Consumer Rights (Payment Surcharges) Regulations
  2012, as amended by SI 2017/752 sch. 8, ban surcharges on consumer
  payment cards; commercial cards remain at cost.
- **United States**: credit cards only (never debit, also prepaid);
  card-network cap 3% (Visa); Connecticut and Massachusetts (G.L. c. 140D
  §28A) forbid it; Colorado caps it at 2%.
- **Canada**: credit cards only, network cap 2.4% (Visa/Mastercard after
  the 2022 class settlement; Canada's 2024 code lowers merchant fees);
  Quebec forbids it.
- **Australia**: the RBA's March 2026 conclusions remove surcharging on
  eftpos, Mastercard and Visa from 2026-10-01.
- **Switzerland** and every country Palee has no reading for: treated as
  "not allowed".

## Decision
1. **Law as code**: `Palee.Payments.Domain.SurchargeLaw.regime(country,
   region, date)` returns the rule for a country (`eea_non_consumer`,
   `commercial_only`, `credit_only`, `any`, `none`), its cap in basis
   points, whether "at cost" applies, whether a region (US state, Canadian
   province, `US-NY`) is needed, and the source URLs. Unknown → `none`.
2. **Per-box setting** `payment_surcharge_settings` (one row per business,
   tenant table with forced RLS): enabled, percent (bps, 0–1000), fixed
   cents (0–10000), channels (`online`, `terminal`, `desk`), country,
   region, `at_cost_confirmed`. `SurchargePolicy.change/4` refuses a
   setting the regime does not allow (`card_surcharge_not_allowed`, reasons
   `not_allowed_here`, `above_cap`, `region_required`,
   `at_cost_required`). The country defaults from the fiscal identity.
3. **Card facts**: saved methods keep `card_funding` (credit, debit,
   prepaid, unknown), `card_country` and `card_commercial` from the
   gateway. A quote applies only when the regime allows that card;
   a card we know nothing about (new card at checkout) is not surcharged
   (`card_unknown`), so Palee never surcharges a card the law forbids.
4. **Quote before paying**: `SurchargePolicy.quote/5` → `applies`,
   `surcharge_cents`, `total_cents`, `reason`. Member endpoints
   `GET /payments/surcharge-quote` and the `surcharge` object on
   `checkout_terms` and `package_terms`; staff `POST
   /admin/payments/surcharge/quote`.
5. **Charging**: `payment_intents.surcharge_cents` holds the surcharge for
   online intents; the gateway is charged `IntentPolicy.total_cents/1`
   (amount + surcharge, terminal stays amount-only because Viva adds its
   own). Autopay drops the surcharge if the total would exceed the
   member's consent maximum.
6. **Desk**: receive-payment accepts `surcharge_cents` and the `card`
   facts only for `card_manual`, checks them against the setting
   (`check_desk`) and records them like the terminal.
7. **Tap to Pay**: with the `terminal` channel off, the sale request sends
   `skipSurcharge=true` to Viva.
8. **Revenue and receipt**: every surcharge is recorded through ADR-264's
   path (`card_surcharge` Finance sale, idempotent per source) and passed
   to the receipt as its own line.

## Rationale
One law module keeps the rules testable and cites its sources. Refusing at
save time (not only at payment) keeps an illegal configuration out of the
database. Quoting from stored card facts avoids surcharging a consumer EEA
card by mistake.

## Alternatives Considered
- **Let each provider decide** (as Viva does on the terminal): Stripe and
  Viva online checkouts do not surcharge by themselves, and the desk card
  machine is outside Palee.
- **Surcharge every card and let staff refund**: illegal in the EEA/UK for
  consumer cards.
- **BIN lookup on new cards before checkout**: needs a provider BIN API;
  left as an open question.

## Consequences
- New cards at online checkout are not surcharged until saved (the
  provider reports funding and country only after the first payment).
- Member-state extra bans (art. 62(5)) are not encoded; the owner
  confirms "at cost" and the accountant confirms the local rule.
- Coach pay (ADR-341) excludes `card_surcharge` rows from commissions.

## Implementation Notes
- Migration `20270501000000_card_surcharge_settings`.
- Endpoints: `GET/PUT /admin/payments/surcharge`,
  `POST /admin/payments/surcharge/quote`, `GET /payments/surcharge-quote`.
- Sources: https://eur-lex.europa.eu/eli/dir/2015/2366/oj,
  https://eur-lex.europa.eu/eli/reg/2015/751/oj,
  https://www.legislation.gov.uk/uksi/2012/3110,
  https://www.legislation.gov.uk/uksi/2017/752/schedule/8,
  https://malegislature.gov/Laws/GeneralLaws/PartI/TitleXX/Chapter140D/Section28A,
  https://www.nickel.com/surcharge-laws,
  https://www.canada.ca/en/financial-consumer-agency/services/merchants/credit-fees-merchant.html,
  https://www.mastercard.com/ca/en/business/support/merchant-surcharge-rules.html,
  https://rba.gov.au/media-releases/2026/mr-26-10.html.
