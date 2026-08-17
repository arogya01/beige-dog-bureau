import Link from "next/link";
import { getCensus } from "@/lib/census";
import type { DogStay, FindingSplit } from "@/lib/types";
import styles from "./page.module.css";

export const dynamic = "force-dynamic";

export default async function BoardPage() {
  const census = await getCensus();
  const coat = census.findings.black_adult;
  const label = census.findings.bully_adult;
  const dogs = [...census.dogs]
    .filter((dog) => dog.open)
    .sort((a, b) => b.days_in_care - a.days_in_care);

  return (
    <div className={styles.room}>
      <div className={styles.fixture} aria-hidden="true">
        <span className={styles.housing}>
          <span className={styles.tube} />
          <span className={styles.tube} />
        </span>
      </div>

      <main id="content" className={styles.wall} tabIndex={-1}>
        <p className={styles.stencil}>AUSTIN ANIMAL CENTER · KENNEL SIDE A</p>

        <div className={styles.frame}>
          <div className={styles.mounts} aria-hidden="true">
            <span />
            <span />
          </div>

          <div className={styles.surface}>
            <p className={styles.ghost} aria-hidden="true">
              OUT&nbsp;&nbsp;ADOPTED&nbsp;&nbsp;GONE
            </p>

            <header className={styles.mast}>
              <div className={styles.titleBlock}>
                <p className={styles.asOf}>rewritten {census.as_of}</p>
                <h1 className={styles.title}>STILL HERE</h1>
                <p className={styles.lede}>
                  These dogs are still in a kennel at Austin Animal Center.
                  This is a staff board, not a pet site. You cannot adopt,
                  search, or apply here.
                </p>
                <p className={styles.count}>
                  <span className={styles.countNum}>{census.open_count}</span>
                  <span> in the building</span>
                </p>
              </div>

              <aside className={styles.notes} aria-label="What the wait follows">
                <Note
                  tone="coat"
                  kicker="the coat"
                  split={coat}
                  yesLabel="black-coat adults"
                  noLabel="other adults"
                  punch="Same wait. Coat is not why they are still here."
                />
                <Note
                  tone="label"
                  kicker="the label"
                  split={label}
                  yesLabel="pit-bull staff label, adults"
                  noLabel="adults without that label"
                  punch="The label is the wait."
                />
              </aside>
            </header>

            <section className={styles.rosterWrap} aria-labelledby="roster-heading">
              <div className={styles.rosterRule}>
                <h2 id="roster-heading" className={styles.rosterHead}>
                  Who is still in the building
                </h2>
                <p className={styles.rosterHint}>
                  Big number = days in care. Each card is one open kennel.
                </p>
              </div>

              <ul className={styles.roster}>
                {dogs.map((dog, i) => (
                  <li key={dog.stay_id} className={styles.slot} data-tilt={String(i % 7)}>
                    <DogCard dog={dog} />
                  </li>
                ))}
              </ul>
            </section>
          </div>

          <footer className={styles.tray}>
            <div className={styles.trayBits} aria-hidden="true">
              <span className={styles.markerBlue} />
              <span className={styles.markerRed} />
              <span className={styles.eraser} />
            </div>
            <p className={styles.cannot}>
              You cannot adopt here. This board only names dogs still inside
              Austin Animal Center.
            </p>
            <Link className={styles.looks} href="/explore">
              All looks
            </Link>
          </footer>
        </div>
      </main>
    </div>
  );
}

function Note({
  tone,
  kicker,
  split,
  yesLabel,
  noLabel,
  punch,
}: {
  tone: "coat" | "label";
  kicker: string;
  split: FindingSplit;
  yesLabel: string;
  noLabel: string;
  punch: string;
}) {
  return (
    <article className={tone === "label" ? styles.noteHot : styles.note}>
      <span className={styles.tape} aria-hidden="true" />
      <h2 className={styles.noteKicker}>{kicker}</h2>
      <p className={styles.notePair}>
        <span>
          <b>{fmtDays(split.med_yes)}</b> days
          <em>{yesLabel}</em>
          <small>n={split.n_yes}</small>
        </span>
        <span className={styles.vs}>{tone === "coat" ? "=" : "vs"}</span>
        <span>
          <b>{fmtDays(split.med_no)}</b> days
          <em>{noLabel}</em>
          <small>n={split.n_no}</small>
        </span>
      </p>
      <p className={styles.punch}>{punch}</p>
    </article>
  );
}

function DogCard({ dog }: { dog: DogStay }) {
  const who = dog.unnamed || !dog.name.trim() ? "NO NAME" : dog.name.trim();
  const longStay = dog.days_in_care >= 90;
  const coat = coatSwatch(dog.color);
  const initial = (dog.name.trim() || "?").slice(0, 1).toUpperCase();
  const flags = [
    dog.bully_label ? "pit-bull staff label" : null,
    dog.senior ? "senior" : null,
    dog.unnamed ? "arrived unnamed" : null,
  ].filter(Boolean);

  const label = [
    `${who}, ${dog.days_in_care} days still in care at Austin Animal Center`,
    dog.breed,
    dog.color ? `coat ${dog.color}` : null,
    dog.age_band,
    ...flags,
  ]
    .filter(Boolean)
    .join(", ");

  return (
    <Link
      className={longStay ? styles.cardLong : styles.card}
      href={`/dog/${encodeURIComponent(dog.stay_id)}`}
      aria-label={label}
    >
      <span className={styles.magnets} aria-hidden="true">
        <span />
        <span />
      </span>
      <span
        className={coat.light ? styles.photoLight : styles.photo}
        style={{ backgroundColor: coat.hex }}
        aria-hidden="true"
      >
        <span>{initial}</span>
      </span>
      <span className={styles.days}>{dog.days_in_care}</span>
      <span className={styles.daysUnit}>{longStay ? "days in — long stay" : "days in"}</span>
      <strong className={styles.who}>{who}</strong>
      <span className={styles.facts}>
        {dog.breed || "breed not written"}
        {dog.color ? ` · ${dog.color}` : ""}
      </span>
      <span className={styles.facts}>
        {dog.age_band}
        {dog.intake_date ? ` · in ${shortDate(dog.intake_date)}` : ""}
      </span>
      {flags.length > 0 ? (
        <span className={styles.flags}>
          {dog.bully_label ? <span className={styles.flagHot}>PIT LABEL</span> : null}
          {dog.senior ? <span className={styles.flag}>SENIOR</span> : null}
          {dog.unnamed ? <span className={styles.flag}>NO NAME IN</span> : null}
        </span>
      ) : null}
    </Link>
  );
}

function fmtDays(n: number): string {
  const rounded = Math.round(n * 10) / 10;
  return Number.isInteger(rounded) ? String(rounded) : rounded.toFixed(1);
}

function shortDate(iso: string): string {
  const [y, m, d] = iso.split("-");
  if (!y || !m || !d) return iso;
  return `${Number(m)}/${Number(d)}/${y.slice(2)}`;
}

function coatSwatch(color: string): { hex: string; light: boolean } {
  const c = color.toLowerCase();
  if (c.includes("white") || c.includes("cream")) return { hex: "#e7e7e1", light: true };
  if (c.includes("yellow") || c.includes("gold")) return { hex: "#c9b15a", light: true };
  if (c.includes("fawn") || c.includes("tan") || c.includes("buff")) return { hex: "#c4a36a", light: true };
  if (c.includes("black")) return { hex: "#2a2a2a", light: false };
  if (c.includes("blue")) return { hex: "#5d6774", light: false };
  if (c.includes("red") || c.includes("rust")) return { hex: "#8b3a2a", light: false };
  if (c.includes("brindle")) return { hex: "#5a4632", light: false };
  if (c.includes("brown") || c.includes("chocolate")) return { hex: "#6b3f24", light: false };
  if (c.includes("gray") || c.includes("grey") || c.includes("silver")) return { hex: "#8a8a88", light: false };
  return { hex: "#6e7468", light: false };
}
