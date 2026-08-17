import type { Metadata } from "next";
import Link from "next/link";
import { Manrope, Sora } from "next/font/google";
import { getCensus } from "@/lib/census";
import type { DogStay } from "@/lib/types";
import styles from "./page.module.css";

export const dynamic = "force-dynamic";

export const metadata: Metadata = {
  title: "All looks · still in care",
  description:
    "Dogs still in care at Austin Animal Center. Four design looks at the same census. This is not a place to adopt.",
};

const display = Sora({
  subsets: ["latin"],
  weight: ["600", "700"],
  display: "swap",
  variable: "--explore-display",
});

const text = Manrope({
  subsets: ["latin"],
  weight: ["400", "500", "600", "700"],
  display: "swap",
  variable: "--explore-text",
});

const LOOKS = [
  {
    href: "/explore/board",
    index: "01",
    name: "Kennel whiteboard",
    promise: "A staff board of who is still in the building — not a pet listing.",
  },
  {
    href: "/explore/press",
    index: "02",
    name: "Investigation cover",
    promise: "A front page that names the wait: the coat matches, the label does not.",
  },
  {
    href: "/explore/clock",
    index: "03",
    name: "Departure board",
    promise: "A holding board. Destination for every dog: still here.",
  },
  {
    href: "/explore/clinic",
    index: "04",
    name: "Intake clipboard",
    promise: "An open-stay clipboard. These dogs have not gone home.",
  },
] as const;

const COPY_ONLY = [
  { href: "/plain", name: "Plain" },
  { href: "/story", name: "Story" },
  { href: "/one", name: "One" },
] as const;

function formatDays(n: number): string {
  const rounded = Math.round(n * 10) / 10;
  return Number.isInteger(rounded) ? String(rounded) : rounded.toFixed(1);
}

function dogName(dog: DogStay): string {
  if (dog.unnamed || !dog.name.trim()) return "Unnamed";
  return dog.name.trim();
}

function shortDate(iso: string): string {
  const [year, month, day] = iso.split("-");
  if (!year || !month || !day) return iso;
  return `${Number(month)}/${Number(day)}/${year.slice(2)}`;
}

export default async function ExplorePage() {
  const census = await getCensus();
  const coat = census.findings.black_adult;
  const label = census.findings.bully_adult;
  const dogs = [...census.dogs]
    .filter((dog) => dog.open !== false)
    .sort((a, b) => b.days_in_care - a.days_in_care || a.stay_id.localeCompare(b.stay_id));

  return (
    <div className={`${styles.stage} ${display.variable} ${text.variable} ${text.className}`}>
      <header className={styles.top}>
        <p className={styles.where}>Austin Animal Center · still in care</p>
        <Link className={styles.looksHere} href="/explore" aria-current="page">
          All looks
        </Link>
      </header>

      <main id="content" className={styles.main} tabIndex={-1}>
        <section className={styles.banner} aria-labelledby="explore-title">
          <p className={styles.kicker}>Public kennel census · not Petfinder</p>
          <h1 id="explore-title" className={styles.title}>
            These dogs are still at the shelter.
          </h1>
          <p className={styles.lede}>
            {census.open_count.toLocaleString()} open stays as of {census.as_of}.
            This page is a public record, not a place to adopt, search, or apply.
            You cannot take a dog home from here.
          </p>
        </section>

        <section className={styles.looks} aria-labelledby="looks-heading">
          <div className={styles.looksHead}>
            <h2 id="looks-heading" className={styles.sectionTitle}>
              Four looks at the same kennel
            </h2>
            <p className={styles.sectionLede}>
              These four change <strong>look and interaction</strong>.{" "}
              {COPY_ONLY.map((item, i) => (
                <span key={item.href}>
                  {i > 0 ? ", " : null}
                  <Link href={item.href}>{item.name}</Link>
                </span>
              ))}{" "}
              only changed copy.
            </p>
          </div>

          <ul className={styles.grid}>
            {LOOKS.map((look) => (
              <li key={look.href}>
                <Link className={styles.card} href={look.href}>
                  <span className={styles.cardIndex}>{look.index}</span>
                  <span className={styles.cardName}>{look.name}</span>
                  <span className={styles.cardPromise}>{look.promise}</span>
                  <span className={styles.cardRoute}>{look.href}</span>
                </Link>
              </li>
            ))}
          </ul>
        </section>

        <section className={styles.findings} aria-labelledby="findings-heading">
          <h2 id="findings-heading" className={styles.sectionTitle}>
            What the wait follows
          </h2>
          <p className={styles.sectionLede}>
            Median days to adoption, adults only. Coat is not the wait. The
            label is.
          </p>
          <div className={styles.splits}>
            <article className={styles.split}>
              <h3 className={styles.splitKicker}>The coat</h3>
              <p className={styles.splitNums}>
                <span>
                  <b>{formatDays(coat.med_yes)}</b> days
                  <span className={styles.who}>black-coat adults</span>
                  <span className={styles.n}>n={coat.n_yes.toLocaleString()}</span>
                </span>
                <span className={styles.eq} aria-label="equals">
                  =
                </span>
                <span>
                  <b>{formatDays(coat.med_no)}</b> days
                  <span className={styles.who}>other adults</span>
                  <span className={styles.n}>n={coat.n_no.toLocaleString()}</span>
                </span>
              </p>
              <p className={styles.splitPunch}>Same wait. The coat is not why they stay.</p>
            </article>
            <article className={`${styles.split} ${styles.splitHot}`}>
              <h3 className={styles.splitKicker}>The label</h3>
              <p className={styles.splitNums}>
                <span>
                  <b>{formatDays(label.med_yes)}</b> days
                  <span className={styles.who}>pit-bull staff label, adults</span>
                  <span className={styles.n}>n={label.n_yes.toLocaleString()}</span>
                </span>
                <span className={styles.eq} aria-label="versus">
                  vs
                </span>
                <span>
                  <b>{formatDays(label.med_no)}</b> days
                  <span className={styles.who}>adults without that label</span>
                  <span className={styles.n}>n={label.n_no.toLocaleString()}</span>
                </span>
              </p>
              <p className={styles.splitPunch}>
                Longer by {formatDays(label.delta)} days. The label is the wait.
              </p>
            </article>
          </div>
        </section>

        <section className={styles.roster} aria-labelledby="roster-heading">
          <div className={styles.rosterHead}>
            <h2 id="roster-heading" className={styles.sectionTitle}>
              Still in care
            </h2>
            <p className={styles.sectionLede}>
              {dogs.length.toLocaleString()} dogs at Austin Animal Center right
              now. Days = time in the building.
            </p>
          </div>
          <ul className={styles.list}>
            {dogs.map((dog) => {
              const who = dogName(dog);
              const flags = [
                dog.bully_label ? "pit-bull staff label" : null,
                dog.senior ? "senior" : null,
                dog.unnamed ? "arrived unnamed" : null,
              ].filter((flag): flag is string => Boolean(flag));
              const labelText = [
                `${who}, ${dog.days_in_care} days still in care at Austin Animal Center`,
                dog.breed,
                dog.color ? `coat ${dog.color}` : null,
                dog.age_band,
                ...flags,
              ]
                .filter(Boolean)
                .join(", ");

              return (
                <li key={dog.stay_id}>
                  <Link
                    className={styles.dog}
                    href={`/dog/${encodeURIComponent(dog.stay_id)}`}
                    aria-label={labelText}
                  >
                    <span className={styles.dogDays}>
                      <b>{dog.days_in_care}</b>
                      <span>days</span>
                    </span>
                    <span className={styles.dogBody}>
                      <strong className={styles.dogName}>{who}</strong>
                      <span className={styles.dogMeta}>
                        {dog.breed || "breed not written"}
                        {dog.color ? ` · ${dog.color}` : ""}
                        {dog.age_band ? ` · ${dog.age_band}` : ""}
                        {dog.intake_date ? ` · in ${shortDate(dog.intake_date)}` : ""}
                      </span>
                      {flags.length > 0 ? (
                        <span className={styles.flags}>
                          {dog.bully_label ? (
                            <span className={styles.flagHot}>pit-bull staff label</span>
                          ) : null}
                          {dog.senior ? <span className={styles.flag}>senior</span> : null}
                          {dog.unnamed ? <span className={styles.flag}>unnamed</span> : null}
                        </span>
                      ) : null}
                    </span>
                  </Link>
                </li>
              );
            })}
          </ul>
        </section>
      </main>

      <footer className={styles.foot}>
        <p>
          You cannot adopt here. This site only names dogs still inside Austin
          Animal Center.
        </p>
        <Link href="/explore">All looks</Link>
      </footer>
    </div>
  );
}
