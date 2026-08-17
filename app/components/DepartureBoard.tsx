import Link from "next/link";
import { getCensus } from "@/lib/census";
import { SplitFlaps } from "@/app/components/SplitFlaps";
import type { DogStay, FindingSplit } from "@/lib/types";
import styles from "@/app/explore/clock/page.module.css";

const MONTHS = [
  "JAN",
  "FEB",
  "MAR",
  "APR",
  "MAY",
  "JUN",
  "JUL",
  "AUG",
  "SEP",
  "OCT",
  "NOV",
  "DEC",
];

function boardDate(iso: string): string {
  const [year, month, day] = iso.split("-");
  const monthIndex = Number(month) - 1;
  if (!year || !day || monthIndex < 0 || monthIndex > 11) return iso;
  return `${day} ${MONTHS[monthIndex]} ${year}`;
}

function formatMed(n: number): string {
  return Number.isInteger(n) ? String(n) : n.toFixed(1);
}

function formatCount(n: number): string {
  return n.toLocaleString("en-US");
}

function dogName(dog: DogStay): string {
  if (dog.unnamed || !dog.name.trim()) return "UNNAMED";
  return dog.name.trim().toUpperCase();
}

function dogNotes(dog: DogStay): string {
  const notes: string[] = [];
  if (dog.bully_label) notes.push("LABEL");
  if (dog.senior) notes.push("SENIOR");
  if (dog.unnamed) notes.push("NO NAME");
  else if (dog.age_band && dog.age_band !== "unknown") notes.push(dog.age_band.toUpperCase());
  return notes.join(" · ") || "—";
}

function FindingRow({
  line,
  status,
  delayed,
}: {
  line: FindingSplit;
  status: "ON TIME" | "DELAYED";
  delayed: boolean;
}) {
  return (
    <div className={delayed ? `${styles.noticeRow} ${styles.noticeRowDelay}` : styles.noticeRow}>
      <span className={styles.noticeKey}>{delayed ? "LABEL" : "COAT"}</span>
      <span className={styles.noticeCopy}>
        {delayed ? (
          <>
            Adults with a pit-bull staff label: {formatMed(line.med_yes)}d median ({formatCount(line.n_yes)}{" "}
            dogs) vs {formatMed(line.med_no)}d without it ({formatCount(line.n_no)}).
          </>
        ) : (
          <>
            Black-coat adults: {formatMed(line.med_yes)}d median ({formatCount(line.n_yes)} dogs) vs{" "}
            {formatMed(line.med_no)}d not black ({formatCount(line.n_no)}).
          </>
        )}
      </span>
      <span className={styles.noticeNums} aria-hidden="true">
        <b>{formatMed(line.med_yes)}</b>
        <i>{delayed ? "VS" : "="}</i>
        <b>{formatMed(line.med_no)}</b>
      </span>
      <span className={delayed ? styles.pillDelay : styles.pillOk}>
        {status}
        {delayed ? ` +${formatMed(line.delta)}` : ""}
      </span>
    </div>
  );
}

export async function DepartureBoard() {
  const census = await getCensus();
  const dogs = [...census.dogs].sort((a, b) => b.days_in_care - a.days_in_care);
  const longest = dogs[0];
  const coat = census.findings.black_adult;
  const label = census.findings.bully_adult;
  const asOf = boardDate(census.as_of);
  const feed = census.source === "snowflake" ? "LIVE FEED" : "SNAPSHOT";

  return (
    <div className={styles.board}>
      <div className={styles.housing}>
        <header className={styles.mast}>
          <div className={styles.mastLeft}>
            <p className={styles.live}>
              <span className={styles.liveDot} aria-hidden="true" />
              <span>
                {feed} · {asOf}
              </span>
            </p>
            <p className={styles.station}>Austin Animal Center</p>
            <p className={styles.product}>Departure board · dogs still in care</p>
          </div>
          <div className={styles.mastRight}>
            <p className={styles.notAdopt}>Not a ticket window. You cannot adopt here.</p>
            <Link className={styles.allLooks} href="/explore">
              All looks
            </Link>
          </div>
        </header>

        <main className={styles.main} id="content" tabIndex={-1}>
          <section className={styles.hero} aria-labelledby="clock-title">
            <p className={styles.eyebrow}>Longest hold on the board</p>
            <h1 className={styles.title} id="clock-title">
              No departures.
            </h1>
            {longest ? (
              <>
                <p className={styles.srOnly}>
                  {dogName(longest)} has been at Austin Animal Center for {longest.days_in_care} days.
                  Destination: still here. This page is not Petfinder.
                </p>
                <div className={styles.heroClock}>
                  <SplitFlaps days={longest.days_in_care} />
                  <p className={styles.heroUnit}>
                    <span>DAYS</span>
                    <span>STILL HERE</span>
                  </p>
                </div>
                <p className={styles.heroWho}>
                  <Link
                    className={styles.heroLink}
                    href={`/dog/${encodeURIComponent(longest.stay_id)}`}
                  >
                    {dogName(longest)}
                  </Link>
                  <span aria-hidden="true"> → </span>
                  <span>still here</span>
                  <span className={styles.heroMeta}>
                    In care since {boardDate(longest.intake_date)}. No departure posted.
                  </span>
                </p>
              </>
            ) : (
              <p className={styles.empty}>No open stays on this census.</p>
            )}
            <p className={styles.heroStandfirst}>
              {formatCount(census.open_count)} dogs are still at the shelter. This is a public
              holding board, not Petfinder, and you cannot take a dog home from this page.
            </p>
          </section>

          <section className={styles.notice} aria-labelledby="notice-heading">
            <div className={styles.noticeHead}>
              <h2 className={styles.noticeTitle} id="notice-heading">
                Service notice
              </h2>
              <p className={styles.noticeFrom}>
                From {formatCount(census.findings.cohort_n)} completed adult adoptions
              </p>
            </div>
            <FindingRow line={coat} status="ON TIME" delayed={false} />
            <FindingRow line={label} status="DELAYED" delayed />
            <p className={styles.thesis}>The coat is not the wait. The label is.</p>
          </section>

          <section className={styles.timetable} aria-labelledby="board-heading">
            <div className={styles.tableHead}>
              <h2 className={styles.tableTitle} id="board-heading">
                Now holding
              </h2>
              <p className={styles.tableCount}>
                {formatCount(dogs.length)} dogs · destination still here
              </p>
              <a className={styles.skipList} href="#board-end">
                Skip the holding list
              </a>
            </div>
            <div className={styles.tableWrap}>
              <table className={styles.table}>
                <caption className={styles.srOnly}>
                  Every dog still in care at Austin Animal Center, ordered by days waiting
                </caption>
                <thead>
                  <tr>
                    <th scope="col">Name</th>
                    <th scope="col">Destination</th>
                    <th scope="col">Remarks</th>
                    <th scope="col">Delay</th>
                  </tr>
                </thead>
                <tbody>
                  {dogs.map((dog) => (
                    <tr key={dog.stay_id} className={dog.bully_label ? styles.rowLabel : undefined}>
                      <th scope="row">
                        <Link
                          className={styles.dogLink}
                          href={`/dog/${encodeURIComponent(dog.stay_id)}`}
                          prefetch={false}
                        >
                          {dogName(dog)}
                          <span className={styles.srOnly}>
                            , still here, {dog.days_in_care} days
                          </span>
                        </Link>
                      </th>
                      <td className={styles.dest}>Still here</td>
                      <td className={styles.notes}>{dogNotes(dog)}</td>
                      <td className={styles.delay}>
                        <span className={styles.delayNum}>{dog.days_in_care}</span>
                        <span className={styles.delayUnit}>d</span>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </section>
        </main>

        <footer className={styles.foot} id="board-end">
          <p>
            You cannot adopt here. These dogs are still in care at Austin Animal Center. This board
            does not place animals, take applications, or list pets for sale.
          </p>
          <p className={styles.footMeta}>
            Census {asOf}
            {census.source === "snapshot"
              ? ` · snapshot ${boardDate(census.generated_at.slice(0, 10))}`
              : " · live warehouse"}
            {" · "}
            <Link href="/explore">All looks</Link>
          </p>
        </footer>
      </div>
    </div>
  );
}
