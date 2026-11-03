# Palee terms of use v3.2: review moderation and training programmes

Date: 2026-11-03
Author: v3.2 legal-terms workstream (draft for Palee's lawyer)
Scope: the new and strengthened sections of `/terms`
(`apps/web/messages/*.json` under `legal.terms`, section list in
`apps/web/src/components/legal/termsSections.ts`).

The brief from ANR: be on Palee's side inside the law, do not constrain the
Palee team without need, and give legal cover for edge cases. Everything
below is written so that no clause is void against a consumer: where a limit
would be void, the text says "as far as the law allows".

## 1. What Palee is, legally, for these two features

- **Reviews.** Palee stores members' reviews and shows them on the box's
  public website, so it is a hosting service (DSA Art. 3(g)(iii)) and, because
  the reviews are disseminated to the public, an online platform
  (Art. 3(i)). Hosting duties (notice and action, Art. 16; statement of
  reasons, Art. 17) apply whatever the provider's size. Section 3 duties
  (Art. 20 internal complaints, Art. 21 out-of-court settlement, Art. 22
  trusted flaggers, Art. 23 misuse suspension, Art. 24 reporting, Art. 25
  dark patterns, Art. 26 ads, Art. 27 recommender transparency) do **not**
  apply to a micro or small enterprise, except Art. 24(3)
  ([DSA Art. 19](https://www.springlex.eu/en/packages/dsa/dsa-regulation/article-19/),
  [notes](https://prighter.com/resources/laws/dsa/articles/article-19)). The
  exemption continues for 12 months after Palee outgrows the threshold
  (Recommendation 2003/361/EC: micro < 10 staff and < EUR 2m, small < 50 staff
  and < EUR 10m). **Deliberate choice:** no appeal flow, no trusted-flagger
  channel, no out-of-court dispute body is promised in the terms. The text
  names only the moderation address and the courts for redress, which Art. 17(3)(f)
  satisfies.
- **Programmes.** The box or coach is the seller and the merchant; Palee is
  the intermediary and never holds the money (ADR-246, ADR-371). That keeps
  Palee out of the consumer contract, out of VAT on the sale and out of
  payment-institution licensing. In exchange Palee owes the marketplace
  information duty of
  [CRD Art. 6a](https://www.iubenda.com/en/help/153021-implementing-the-omnibus-directive-for-online-marketplaces)
  (inserted by Omnibus Directive (EU) 2019/2161): it must say whether the
  third party selling is a trader, and it may rely on that party's own
  declaration. The terms therefore state that boxes, coaches and sellers
  declare they act as traders (`boxesBody`, `programmesBody1`).

## 2. Clause by clause

### 2.1 «Κριτικές και αναφορές περιεχομένου» / "Reviews and content reports"

| Paragraph | What it says | Why |
|---|---|---|
| `reviewsBody1` | Only people who checked in may review, one each, own experience only, no paid or solicited reviews, no insults, no third-party personal data, no ads, nothing unlawful. | DSA Art. 14(1): the terms must state the restrictions imposed on user content. The paid-review ban mirrors UCPD Annex I points 23b/23c (as amended by Dir. (EU) 2019/2161) and [Google's review policies](https://support.google.com/contributionpolicy/answer/7400114), which Palee's list is modelled on (fake engagement, personal information, off topic, spam, harassment). |
| `reviewsBody2` | Members and the box may report with one of six reasons (note required for "unlawful" and "something else"); visitors by email to `moderation@palee.app`, the address in each box website footer; reports in any language; receipt confirmed. | [DSA Art. 16(1)–(2)](https://prighter.com/resources/laws/dsa/articles/article-16): an easy, electronic notice mechanism open to **any** person, precise and substantiated notices, and Art. 16(4) confirmation of receipt. The email channel is the cheapest compliant channel for visitors (ADR-397 decision 4: no public form yet). |
| `reviewsBody3` | Only the Palee team decides; a report changes nothing; a box can never hide a review of itself; no automatic hiding; a human decides; handling is timely, diligent, non-arbitrary, objective. | Art. 16(6) (timely, diligent, non-arbitrary, objective; automated means must be disclosed, so saying there are none is the strongest version), Art. 14(4) (diligent, objective, proportionate enforcement with regard to fundamental rights). **Deliberate choice in Palee's favour:** it also protects Palee and the boxes from the UCPD ban on misrepresenting consumer reviews, and removes the whole "the gym made you delete my review" class of complaint. |
| `reviewsBody4` | Three outcomes (keep / hide / remove); on hide or remove the author gets a statement of reasons with the ground, the legal or contractual basis, that a human decided, and redress at `moderation@palee.app` and the courts; the reporter hears the outcome; a hidden review can be restored with a statement. | DSA Art. 17(1) and (3)(a)–(f), and Art. 16(5) (the notifier is told the decision and the redress available). The statement deliberately does **not** promise an internal appeal, because Art. 20 does not bind a small enterprise (Art. 19). |
| `reviewsBody5` | One open report per person and review, ten a day per box; Palee may refuse reports from repeat abusers and suspend abusive accounts; removed texts and notes kept 6 months, statement kept; no prior checking and no monitoring duty; Palee may act on its own, with or without a report; programme reviews may be hidden by the seller with a reason and never edited or deleted. | Misuse: the idea of Art. 23 applied voluntarily and at Palee's discretion, which is a freedom, not a duty, for a small enterprise. No monitoring duty: DSA Art. 8 (no general monitoring obligation) plus the own-initiative wording of Art. 7 (voluntary investigations do not cost the hosting liability shield of Art. 6). Retention: GDPR Art. 5(1)(c) and (e); the statement must survive because it is the record of the restriction. Programme reviews follow ADR-370 decision 6. |

Also strengthened: `contentBody` now carries the **licence** Palee needs (non-exclusive, royalty-free, for as long as the content is posted plus backups), a ban on content the poster has no right to post, and the express discretion to remove, hide or **limit the dissemination** of content. The three measures are the exact wording of DSA Art. 17(1)(a) ("restrictions of the visibility"), which keeps every future moderation tool (down-ranking, shadow-limits) inside what the terms already announce. Comparable: [Teachable](https://teachable.com/terms-of-use) §4.2/5.7 (licence plus removal without warning at the operator's discretion).

### 2.2 «Προγράμματα προπόνησης» / "Training programmes"

| Paragraph | What it says | Why |
|---|---|---|
| `programmesBody1` | The seller is the box or coach, declares it acts as a trader, and answers for the content, description, price, VAT, receipt and the buyer's consumer rights; Palee is not a party. | CRD Art. 6a (trader-status disclosure, based on the seller's declaration); the "not a party" framing follows [Teachable](https://teachable.com/terms-of-use) §1.2/11.2 and Mindbody's intermediary framing. It keeps Palee out of DCD 2019/770 conformity liability, which falls on the trader supplying the digital content. |
| `programmesBody2` | Payment inside Palee but into the seller's own account with the seller's provider; Palee never holds the money; no commission today; a change is shown in the price and announced to sellers first. | ADR-246/371. "No commission today" with notice, not "never": it keeps a commission possible without rewriting the terms, while P2B Art. 3 requires the terms of a change to be notified to business users in advance. |
| `programmesBody3` | Start date today up to +60 days; workouts land from that date; preview day titles; the buyer keeps the version bought; a new price or refund rule binds later buyers only. | ADR-370 decisions 3–5; DCD 2019/770 Art. 19 would make a unilateral change of paid digital content a problem, so freezing versions is both the product rule and the safe rule. |
| `programmesBody4` | 14-day withdrawal for consumers where the seller is in the EU, EEA or UK; an express request to start is asked only when the start falls inside the 14 days, never pre-ticked; pro rata deduction on withdrawal; full refund where the start is later; the amount is shown before confirming. | [CRD Art. 16(a) and (m)](https://www.legislation.gov.uk/eudr/2011/83/article/16) and [Art. 14(3)–(4)](https://www.legislation.gov.uk/eudr/2011/83/article/14): proportional payment only where the consumer expressly requested performance to begin, and **no cost at all** where that request or the acknowledgement is missing. In Greece this is Law 2251/1994 arts 3θ and 3ιβ as amended by Law 4933/2022 (Omnibus) and Law 4967/2022 (DCD); see [Greek Omnibus transposition](https://www.mondaq.com/dodd-frank-consumer-protection-act/1231048/greece-implemented-the-omnibus-directive-is-your-business-ready) and [Law 4933/2022 art. 21](https://www.taxheaven.gr/law/4933/2022/arthro/21). **Deliberate choice:** ADR-371 keeps the service reading (pro rata) instead of the digital-content reading of Art. 16(m) (total loss of the right). The pro rata rule is the one that cannot be attacked; the Art. 16(m) reading would be worth more to sellers but is the one a court is most likely to strike for a dated, coached programme. The cost of being safe is small, and the seller's own rule may always give more. |
| `programmesBody5` | The seller's refund rule on top of the law (three options), copied onto the purchase, shown before buying; the better of rule and law wins; the seller refunds through its own provider; the apps do not sell programmes; a programme is general training information, not medical advice, and promises no result; ask the seller first, then Palee. | The "better of the two wins" sentence is what makes the three rules lawful: a rule narrower than the law can never cut the statutory right (CRD Art. 25, Law 2251/1994 art. 2(6) on unfair terms). ADR-256 for the store apps. The no-result line answers the UCPD rules on health claims and keeps Palee clear of being read as a coach. |

Greece also now requires an online **withdrawal button** for distance
contracts (reported as Act 5317/2026 inserting a new article into Law
2251/1994, [EY alert](https://www.ey.com/en_gr/technical/tax/tax-alerts/new-requirement-to-implement-an-online-withdrawal-button-on-distance-selling-contracts)).
Palee already has the in-app «Υπαναχώρηση» button on the purchase
(ADR-371 s6 A), and the terms now name it. This is on the lawyer list below,
because the act's form requirements were not verifiable from primary sources
on 2026-11-03.

### 2.3 «Για τα box και τους προπονητές» / "For boxes and coaches"

| Paragraph | What it says | Why |
|---|---|---|
| `businessBody1` | The business answers for its uploads, prices, receipts, taxes, licences and for its members' data as controller, and licenses its name, logo and content for use in the service, its website and (if chosen) the programme store. | ADR-267 already splits the controller roles; the licence makes the box website and the marketplace listing contractually safe. |
| `businessBody2` | Palee may restrict, suspend or stop the service for breach or non-payment, gives reasons on a durable medium before or when a restriction takes effect, 30 days' notice before stopping the service, with exceptions for legal duties, urgent risk and repeated serious breaches; complaints go to the contact address and get an answer in a reasonable time. | [P2B Regulation (EU) 2019/1150 Art. 4(1), (2), (4) and (5)](https://www.legislation.gov.uk/eur/2019/1150/article/4). **Deliberate choice:** Palee is a small enterprise, so [Art. 11(5)](https://www.legislation.gov.uk/eur/2019/1150/article/11) exempts it from a formal internal complaint-handling system and Art. 12(5) from naming mediators. The clause therefore promises an address and a reasonable answer, and no process, no deadlines and no mediators. If Palee grows past 50 staff or EUR 10m, both duties switch on. |
| `businessBody3` | The business indemnifies Palee for claims arising from its own acts, content or member relationship, as far as the law allows; not against consumers. | Standard operator protection (Teachable §17). B2B only, because an indemnity against a consumer would be an unfair term (Law 2251/1994 art. 2). |

### 2.4 Liability, law and changes

- `liabilityBody`: as-is provision, no liability for box or seller contracts,
  for others' content, for misuse of a feature or for training itself; no
  indirect loss; a cap at the fees of the last twelve months, or EUR 100 where
  nothing was paid; carve-outs for intent, gross negligence, death and personal
  injury; consumer rights untouched. The twelve-month cap is the common SaaS
  cap (Teachable §17). The carve-outs are not generosity: under Greek Civil
  Code art. 332 an exclusion for intent or gross negligence is void, and a cap
  with no carve-out risks the whole clause. Palee's free users are the reason
  for the EUR 100 floor: without it a cap of "what you paid" is zero and a court
  may read the clause as a total exclusion.
- `lawBody`: Greek law, courts of Athens, with the consumer keeping their home
  law and home forum. This is the only lawful version: Brussels I bis Arts
  17–19 and Rome I Art. 6 make a consumer forum clause unenforceable, so
  claiming Athens against consumers would risk the clause rather than win
  anything. Against businesses the clause works in full. An ADR body is named
  as optional for the user and not accepted by Palee, since Palee is not bound
  to ADR (DSA Art. 21 is a Section 3 duty, exempt under Art. 19).
- `changesBody`: notice in the app before a change to the terms takes effect
  (DSA Art. 14(2)), continued use counts as acceptance, and an express right
  to add, change or stop features, set reasonable use limits and run tests
  with part of the user base. The one promise: nothing paid for is taken away
  without notice. This is the "do not constrain the Palee team" clause.

## 3. Other jurisdictions, at a high level

- **UK.** The Online Safety Act 2023 illegal-content duties apply to small
  user-to-user services as well; there is no size exemption, and Ofcom
  restated in its open letter of 28 August 2026 that the duties are live
  ([Ofcom](https://www.ofcom.org.uk/siteassets/resources/documents/about-ofcom/public-correspondence/2026/open-letter-on-reminding-services-of-their-duties-under-the-osa-28-august-2026.pdf),
  [practitioner summary](https://bratby.law/online-safety-act-duties/)). Palee's
  reporting route, human review, record keeping and removal powers are the
  substance of what a low-risk small service needs; a UK risk assessment is a
  separate piece of work, not a terms clause. Consumer withdrawal for UK
  buyers follows the Consumer Contracts (Information, Cancellation and
  Additional Charges) Regulations 2013, which reproduce CRD Arts 14 and 16, so
  the same pro rata wording holds.
- **US.** Section 230(c)(1) of the Communications Decency Act keeps Palee from
  being treated as the publisher of a member's review, and (c)(2) protects
  good-faith removal. The terms' "we may remove, no duty to monitor" wording
  is what preserves that posture. Nothing in the drafting relies on it.

## 4. Comparable platforms read

- [Teachable Terms of Use](https://teachable.com/terms-of-use) (seller is the
  creator, payment agent, 14-day refund default, licence to user content,
  removal at discretion, 12-month liability cap, indemnity, one-year claim
  window).
- [Google review content policies](https://support.google.com/contributionpolicy/answer/7400114)
  (the six-reason taxonomy, fake engagement and personal-information rules).
- Tripadvisor's content integrity policy (operator decides on reported
  reviews, businesses cannot remove them) could not be fetched on 2026-11-03
  (HTTP 403); the Google policies carried the same points.
- Mindbody's terms of service could not be fetched (redirect to a marketing
  page); its intermediary framing is reflected in `boxesBody`, which predates
  this work.

## 5. For the lawyer to confirm

1. **Art. 16(m) or the service reading?** ADR-371 chose pro rata with the
   express request. Confirm whether a dated, coached programme can instead be
   treated as digital content with a full loss of the withdrawal right, and
   whether we may offer sellers that option. The upside for sellers is large.
2. **Greek withdrawal button (Act 5317/2026).** Does the in-app
   «Υπαναχώρηση» button on the purchase satisfy the new form requirement, and
   does the duty fall on the seller, on Palee, or on both?
3. **Micro/small status.** Confirm Palee's current headcount and turnover on a
   consolidated basis, so that the absence of DSA Art. 20–27 duties and of a
   P2B internal complaint system is sound, and set a yearly re-check.
4. **Liability cap.** Is the twelve-month cap with a EUR 100 floor enforceable
   against business users in Greece, and is the carve-out list complete
   (Civil Code arts 332 and 334, Law 2251/1994 art. 2)?
5. **Indemnity from businesses.** Enforceable as drafted, and should it carry
   a cap or a defence-control clause?
6. **Forum.** Athens courts for business users: exclusive or non-exclusive?
7. **Trader declaration.** Is the seller's declaration enough for CRD Art. 6a,
   or must Palee also show the seller's identity and VAT number on the
   programme page?
8. **Statement of reasons wording.** Confirm that the terms, and not only the
   law, are a valid "contractual ground" for the non-illegal grounds
   (DSA Art. 17(3)(d)/(e)), and that the six report reasons are described
   precisely enough in Art. 14(1) terms.
9. **Retention.** Is six months the right period for a removed review's text
   and the reporter's note, against a possible claim window?
10. **Placeholders.** `providerBody` still carries the bracketed company name,
    address and contact; the law section now names Greek law and Athens
    directly, so the `[governing law and competent courts]` placeholder was
    dropped from the catalogs. Confirm both. The draft date shown on both
    legal pages (`LEGAL_DRAFT_DATE`) is now 2026-11-03.
