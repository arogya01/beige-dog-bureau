import Link from "next/link";
import { notFound } from "next/navigation";
import { LetterForm } from "@/app/components/LetterForm";
import { SplitFlaps } from "@/app/components/SplitFlaps";
import { getDog } from "@/lib/census";
import type { DogStay } from "@/lib/types";
import board from "@/app/explore/clock/page.module.css";
import styles from "./page.module.css";

export const dynamic = "force-dynamic";

const MONTHS = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"];

function boardDate(iso: string): string {
  const [year, month, day] = iso.split("-");
  const monthIndex = Number(month) - 1;
  if (!year || !day || monthIndex < 0 || monthIndex > 11) return iso;
  return `${day} ${MONTHS[monthIndex]} ${year}`;
}

function fmt(n: number): string {
  return Number.isInteger(n) ? String(n) : n.toFixed(1);
}

function count(n: number): string {
  return n.toLocaleString("en-US");
}

function dogName(dog: DogStay): string {
  if (dog.unnamed || !dog.name.trim()) return "Unnamed";
  return dog.name.trim();
}

/** One row of the manifest. `tone` decides whether the field is implicated. */
function Field({
  label,
  value,
  tone = "plain",
}: {
  label: string;
  value: string;
  tone?: "plain" | "flagged" | "clear";
}) {
  const cls =
    tone === "flagged"
      ? `${styles.field} ${styles.fieldFlagged}`
      : tone === "clear"
        ? `${styles.field} ${styles.fieldClear}`
        : styles.field;
  return (
    <div className={cls}>
      <p className={styles.key}>{label}</p>
      <p className={tone === "plain" ? styles.val : `${styles.val} ${styles.valAmber}`}>{value}</p>
    </div>
  );
}

export default async function CaseFilePage({
  params,
}: {
  params: Promise<{ stayId: string }>;
}) {
  const { stayId } = await params;
  const found = await getDog(decodeURIComponent(stayId));
  if (!found) notFound();
  const { dog, census } = found;

  const coat = census.findings.black_adult;
  const label = census.findings.bully_adult;
  const feed = census.source === "snowflake" ? "LIVE FEED" : "SNAPSHOT";
  const asOf = boardDate(census.as_of);

  return (
    <div className={board.board}>
      <div className={board.housing}>
        <header className={board.mast}>
          <div className={board.mastLeft}>
            <p className={board.live}>
              <span className={board.liveDot} aria-hidden="true" />
              <span>
                {feed} · {asOf}
              </span>
            </p>
            <p className={board.station}>Austin Animal Center</p>
            <p className={styles.fileNo}>Case file · stay {dog.stay_id}</p>
          </div>
          <div className={board.mastRight}>
            <p className={board.notAdopt}>Not a ticket window. You cannot adopt here.</p>
            <Link className={styles.back} href="/">
              ← All departures
            </Link>
          </div>
        </header>

        <main className={board.main} id="content" tabIndex={-1}>
          <section className={styles.head} aria-labelledby="file-title">
            <p className={styles.eyebrow}>Destination · still here</p>
            <h1 className={styles.name} id="file-title">
              {dogName(dog)}
            </h1>
            <p className={styles.sub}>
              Animal {dog.animal_id} · in care since {boardDate(dog.intake_date)}
            </p>
            <p className={board.srOnly}>
              {dogName(dog)} has been at Austin Animal Center for {dog.days_in_care} days. No
              departure is posted. This page does not place a dog.
            </p>
            <div className={styles.clock}>
              <SplitFlaps days={dog.days_in_care} />
              <p className={styles.unit}>
                <span>DAYS</span>
                <span>STILL HERE</span>
              </p>
            </div>
          </section>

          <section className={styles.section} aria-labelledby="manifest-heading">
            <div className={styles.sectionHead}>
              <h2 className={styles.sectionTitle} id="manifest-heading">
                Manifest
              </h2>
              <p className={styles.sectionNote}>As recorded by Austin Animal Center</p>
            </div>
            <div className={styles.manifest}>
              <Field label="Coat" value={dog.color || "Not recorded"} tone="clear" />
              <Field
                label="Breed field"
                value={dog.breed || "Not recorded"}
                tone={dog.bully_label ? "flagged" : "plain"}
              />
              <Field
                label="Age band"
                value={`${dog.age_band}${dog.age_years != null ? ` · ${dog.age_years} yr` : ""}`}
              />
              <Field label="Arrived named?" value={dog.unnamed ? "No" : "Yes"} />
              <Field
                label="Bully-type label"
                value={dog.bully_label ? "Yes" : "No"}
                tone={dog.bully_label ? "flagged" : "plain"}
              />
              <Field label="Intake type" value={dog.source_name || "Not recorded"} />
              <Field label="Found" value={dog.found_address || "Not recorded"} />
              <Field label="Overlooked index" value={String(dog.index)} />
            </div>
          </section>

          <section className={styles.section} aria-labelledby="verdict-heading">
            <div className={styles.sectionHead}>
              <h2 className={styles.sectionTitle} id="verdict-heading">
                Service notice
              </h2>
              <p className={styles.sectionNote}>
                From {count(census.findings.cohort_n)} completed adult adoptions
              </p>
            </div>
            <div className={styles.verdict}>
              <div className={styles.vRow}>
                <span className={styles.vKey}>COAT</span>
                <p className={styles.vCopy}>
                  This dog&rsquo;s coat is recorded as {dog.color || "not recorded"}. Across the
                  cohort, an all-black coat waits {fmt(coat.med_yes)}d against {fmt(coat.med_no)}d
                  &mdash; a gap a permutation test cannot separate from chance (p ={" "}
                  {coat.p.toFixed(2)}). It does not predict this file.
                </p>
                <span className={styles.pillOk}>On time</span>
              </div>
              <div className={dog.bully_label ? `${styles.vRow} ${styles.vRowDelay}` : styles.vRow}>
                <span className={styles.vKey}>LABEL</span>
                <p className={styles.vCopy}>
                  {dog.bully_label ? (
                    <>
                      The breed field on this file carries a bully-type label. Adults carrying that
                      label wait {fmt(label.med_yes)}d against {fmt(label.med_no)}d without it (p ={" "}
                      {label.p.toFixed(4)}) &mdash; a {fmt(label.delta)}-day penalty attached to
                      typed text, not to a dog.
                    </>
                  ) : (
                    <>
                      The breed field on this file carries no bully-type label. Adults that do wait{" "}
                      {fmt(label.med_yes)}d against {fmt(label.med_no)}d (p = {label.p.toFixed(4)}).
                      This is the one field in the dataset that moves the wait.
                    </>
                  )}
                </p>
                <span className={dog.bully_label ? styles.pillDelay : styles.pillMuted}>
                  {dog.bully_label ? `Delayed +${fmt(label.delta)}` : "Not flagged"}
                </span>
              </div>
              <p className={styles.thesis}>The coat is not the wait. The label is.</p>
            </div>
          </section>

          <section className={styles.section} aria-labelledby="letter-heading">
            <div className={styles.sectionHead}>
              <h2 className={styles.sectionTitle} id="letter-heading">
                Letter from the file
              </h2>
              <p className={styles.sectionNote}>Cortex may answer only from this row</p>
            </div>
            <LetterForm
              dog={dog}
              // textarea and button are styled by `.letter textarea` /
              // `.letter button`, so only the wrapper needs naming. The label
              // is visually hidden because the section heading already says it.
              ui={{
                form: styles.letter,
                label: board.srOnly,
                reply: styles.reply,
                source: styles.source,
              }}
            />
          </section>
        </main>

        <footer className={styles.foot}>
          <p>
            You cannot adopt from this page. This dog is still in care at Austin Animal Center. The
            Bureau does not place animals, take applications, or list pets for sale.
          </p>
          <p className={styles.footMeta}>
            Census {asOf} ·{" "}
            <a href="https://data.austintexas.gov/Health-and-Community-Services/Austin-Animal-Center-Intakes/wter-evkm">
              Austin open data
            </a>{" "}
            · <Link href="/">All departures</Link>
          </p>
        </footer>
      </div>
    </div>
  );
}
