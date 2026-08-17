import Link from "next/link";
import { getCensus } from "@/lib/census";
import type { DogStay, FindingSplit } from "@/lib/types";
import styles from "./page.module.css";

export const dynamic = "force-dynamic";

function formatDays(n: number): string {
  const v = Math.round(n * 10) / 10;
  return Number.isInteger(v) ? String(v) : v.toFixed(1);
}

function formatP(p: number): string {
  if (p < 0.001) return "<0.001";
  return p.toFixed(4).replace(/0+$/, "").replace(/\.$/, "");
}

function displayName(dog: DogStay): string {
  if (dog.unnamed || !dog.name.trim()) return "Unnamed on intake";
  return dog.name;
}

function longestWait(dogs: DogStay[]): DogStay | null {
  return dogs.reduce<DogStay | null>((best, dog) => {
    if (!best || dog.days_in_care > best.days_in_care) return dog;
    return best;
  }, null);
}

export default async function ClinicPage() {
  const census = await getCensus();
  const coat = census.findings.black_adult;
  const label = census.findings.bully_adult;
  const lead = longestWait(census.dogs);
  const rest = lead
    ? [...census.dogs]
        .filter((dog) => dog.stay_id !== lead.stay_id)
        .sort((a, b) => b.days_in_care - a.days_in_care || a.stay_id.localeCompare(b.stay_id))
    : [];

  return (
    <div className={styles.wall}>
      <header className={styles.rail}>
        <p className={styles.facility}>
          Austin Animal Center
          <span aria-hidden="true"> · </span>
          Kennel census
          <span aria-hidden="true"> · </span>
          As of {census.as_of}
        </p>
        <Link className={styles.looks} href="/explore">
          All looks
        </Link>
      </header>

      <main id="content" className={styles.sheet} tabIndex={-1}>
        <p className={styles.notice} role="status">
          These dogs are still in care at the shelter. This page is an admin
          record, not a place to adopt.
        </p>

        <div className={styles.intro}>
          <h1 className={styles.title}>Intake clipboard</h1>
          <p className={styles.lede}>
            {census.open_count.toLocaleString()} open stays. Printed from the
            kennel census. You cannot take a dog home from this site.
          </p>
        </div>

        {lead ? (
          <div className={styles.clipboard}>
            <div className={styles.clip} aria-hidden="true">
              <span className={styles.clipCap} />
              <span className={styles.clipArm} />
              <span className={styles.clipPad} />
            </div>
            <article className={styles.form}>
              <p className={styles.formHead}>
                <span>City of Austin — Animal Services</span>
                <span>Form AAC-17 · Open stay</span>
              </p>
              <p className={styles.stamp} role="note">
                Not adoptable on this site
              </p>
              <h2 className={styles.patient}>{displayName(lead)}</h2>
              <p className={styles.statusLine}>
                Status: still in care · {formatDays(lead.days_in_care)} days
                housed · intake {lead.intake_date}
              </p>
              <dl className={styles.fields}>
                <div>
                  <dt>Stay ID</dt>
                  <dd>{lead.stay_id}</dd>
                </div>
                <div>
                  <dt>Days in care</dt>
                  <dd>{formatDays(lead.days_in_care)}</dd>
                </div>
                <div>
                  <dt>Intake date</dt>
                  <dd>{lead.intake_date}</dd>
                </div>
                <div>
                  <dt>Age band</dt>
                  <dd>
                    {lead.age_band}
                    {lead.senior ? " · senior" : ""}
                  </dd>
                </div>
                <div>
                  <dt>Coat</dt>
                  <dd>{lead.color || "Not recorded"}</dd>
                </div>
                <div>
                  <dt>Breed field</dt>
                  <dd>{lead.breed || "Not recorded"}</dd>
                </div>
                <div>
                  <dt>Staff label</dt>
                  <dd>
                    {lead.bully_label ? "Pit-bull type on file" : "No pit-bull staff label"}
                  </dd>
                </div>
                <div>
                  <dt>Named at intake</dt>
                  <dd>{lead.unnamed ? "No" : "Yes"}</dd>
                </div>
              </dl>
              <p className={styles.formFoot}>
                Longest open stay on this census.{" "}
                <Link href={`/dog/${encodeURIComponent(lead.stay_id)}`}>
                  Open this record
                </Link>
              </p>
            </article>
          </div>
        ) : (
          <p className={styles.empty}>No open stays in this census.</p>
        )}

        <section className={styles.labs} aria-labelledby="labs-heading">
          <h2 id="labs-heading" className={styles.sectionTitle}>
            Lab comparison · adopted adults
          </h2>
          <p className={styles.sectionNote}>
            Closed-stay medians from {census.findings.cohort_n.toLocaleString()}{" "}
            adoptions. Coat is not the wait. The label is.
          </p>
          <div className={styles.labRow}>
            <LabStrip
              code="01"
              title="Coat color"
              analyteYes="Black-coat adult"
              analyteNo="Other-coat adult"
              split={coat}
              verdict="No wait effect. Medians match."
              critical={false}
            />
            <LabStrip
              code="02"
              title="Staff breed label"
              analyteYes="Pit-bull label, adult"
              analyteNo="No such label, adult"
              split={label}
              verdict={`Prolonged stay. +${formatDays(label.delta)} days.`}
              critical
            />
          </div>
        </section>

        <section className={styles.tray} aria-labelledby="tray-heading">
          <h2 id="tray-heading" className={styles.sectionTitle}>
            Remaining open stays
          </h2>
          <p className={styles.sectionNote}>
            {rest.length.toLocaleString()} thinner slips, longest wait first.
            Each animal is still housed. None can be adopted here.
          </p>
          {rest.length > 0 ? (
            <ol className={styles.stack}>
              {rest.map((dog) => (
                <li key={dog.stay_id}>
                  <Link
                    className={styles.slip}
                    href={`/dog/${encodeURIComponent(dog.stay_id)}`}
                  >
                    <span className={styles.slipDays}>
                      <strong>{formatDays(dog.days_in_care)}</strong>
                      <span>days in care</span>
                    </span>
                    <span className={styles.slipBody}>
                      <span className={styles.slipName}>{displayName(dog)}</span>
                      <span className={styles.slipMeta}>
                        {dog.breed || "Breed not recorded"}
                        <span aria-hidden="true"> · </span>
                        {dog.color || "Coat not recorded"}
                        <span aria-hidden="true"> · </span>
                        in since {dog.intake_date}
                      </span>
                    </span>
                    <span className={styles.slipFlags}>
                      <span className={styles.flag}>Open stay</span>
                      {dog.bully_label ? (
                        <span className={styles.flagHot}>Pit-bull label</span>
                      ) : (
                        <span className={styles.flag}>No pit label</span>
                      )}
                      {dog.senior ? <span className={styles.flag}>Senior</span> : null}
                    </span>
                  </Link>
                </li>
              ))}
            </ol>
          ) : (
            <p className={styles.empty}>No additional open stays.</p>
          )}
        </section>
      </main>

      <footer className={styles.colophon}>
        <p>
          You cannot adopt here. This clipboard is a public admin record of
          dogs still in care at Austin Animal Center. Go to the shelter — not
          this page — if you want to take a dog home.
        </p>
        <p className={styles.printMeta}>
          Census {census.source} · generated {census.generated_at} · as of{" "}
          {census.as_of}
        </p>
      </footer>
    </div>
  );
}

function LabStrip({
  code,
  title,
  analyteYes,
  analyteNo,
  split,
  verdict,
  critical,
}: {
  code: string;
  title: string;
  analyteYes: string;
  analyteNo: string;
  split: FindingSplit;
  verdict: string;
  critical: boolean;
}) {
  return (
    <article className={critical ? `${styles.lab} ${styles.labHot}` : styles.lab}>
      <p className={styles.labHead}>
        <span>
          Assay {code} · {title}
        </span>
        <span className={critical ? styles.labFlagHot : styles.labFlag}>
          {critical ? "CRIT" : "NEG"}
        </span>
      </p>
      <table className={styles.labTable}>
        <caption className={styles.srOnly}>
          Median days to adoption for {title}
        </caption>
        <thead>
          <tr>
            <th scope="col">Analyte</th>
            <th scope="col">Median days</th>
            <th scope="col">n</th>
          </tr>
        </thead>
        <tbody>
          <tr>
            <th scope="row">{analyteYes}</th>
            <td>{formatDays(split.med_yes)}</td>
            <td>{split.n_yes.toLocaleString()}</td>
          </tr>
          <tr>
            <th scope="row">{analyteNo}</th>
            <td>{formatDays(split.med_no)}</td>
            <td>{split.n_no.toLocaleString()}</td>
          </tr>
        </tbody>
      </table>
      <p className={styles.labDelta}>
        Δ {split.delta > 0 ? "+" : ""}
        {formatDays(split.delta)} days · p {formatP(split.p)}
      </p>
      <p className={styles.labVerdict}>{verdict}</p>
    </article>
  );
}
