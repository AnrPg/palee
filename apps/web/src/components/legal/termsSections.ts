/**
 * ADR-267: the sections of Palee's terms of use, in the order they are read.
 * Each one: its anchor, then the keys of its heading and of its paragraphs in
 * `legal.terms`. `provider` is rendered first by the page itself.
 */
export const TERMS_SECTIONS = [
  { id: "account", heading: "accountTitle", texts: ["accountBody"] },
  { id: "boxes", heading: "boxesTitle", texts: ["boxesBody"] },
  // ADR-370/371 and Regulation (EU) 2019/1150: what a business using Palee answers for.
  { id: "business", heading: "businessTitle", texts: ["businessBody1", "businessBody2", "businessBody3"] },
  { id: "payments", heading: "paymentsTitle", texts: ["paymentsBody"] },
  // ADR-370/371: selling and buying a training programme.
  {
    id: "programmes",
    heading: "programmesTitle",
    texts: ["programmesBody1", "programmesBody2", "programmesBody3", "programmesBody4", "programmesBody5"],
  },
  { id: "content", heading: "contentTitle", texts: ["contentBody"] },
  // ADR-397 and DSA Art. 14: reviews, reports and who decides on them.
  {
    id: "reviews",
    heading: "reviewsTitle",
    texts: ["reviewsBody1", "reviewsBody2", "reviewsBody3", "reviewsBody4", "reviewsBody5"],
  },
  { id: "health", heading: "healthTitle", texts: ["healthBody"] },
  { id: "ai", heading: "aiTitle", texts: ["aiBody"] },
  { id: "availability", heading: "availabilityTitle", texts: ["availabilityBody"] },
  { id: "ending", heading: "endingTitle", texts: ["endingBody"] },
  { id: "liability", heading: "liabilityTitle", texts: ["liabilityBody"] },
  { id: "law", heading: "lawTitle", texts: ["lawBody"] },
  { id: "changes", heading: "changesTitle", texts: ["changesBody"] },
] as const;

/** ADR-397 decision 4: the address every statement of reasons and box website footer names. */
export const MODERATION_CONTACT = "moderation@palee.app";
