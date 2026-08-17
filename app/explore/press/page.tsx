import type { Metadata } from "next";
import Link from "next/link";
import { Cormorant_Garamond, Source_Sans_3 } from "next/font/google";
import { getCensus } from "@/lib/census";
import type { DogStay, FindingSplit } from "@/lib/types";
import styles from "./page.module.css";

export const dynamic = "force-dynamic";

export const metadata: Metadata = {
  title: "Investigation cover · still in care",
  description:
    "Dogs still in care at Austin Animal Center. This is not a place to adopt. The coat is not the wait. The label is.",
};

const serif = Cormorant_Garamond({
  subsets: ["latin"],
  weight: ["500", "600", "700"],
  style: ["normal", "italic"],
  display: "swap",
  variable: "--press-serif",
});

const sans = Source_Sans_3({
  subsets: ["latin"],
  weight: ["400", "500", "600", "700"],
  display: "swap",
  variable: "--press-sans",
});

function formatDays(n: number): string {
  return Number.isInteger(n) ? String(n) : n.toFixed(1);
}

function formatP(p: number): string {
  if (p < 0.001) return p < 0.0001 ? "p < 0.0001" : `p = ${p.toFixed(4)}`;
  return `p = ${p.toFixed(2)}`;
}

function formatDateline(iso: string): string {
  const [year, month, day] = iso.split("-").map(Number);
  const months = [
    "January",
    "February",
    "March",
    "April",
    "May",
    "June",
    "July",
    "August",
    "September",
    "October",
    "November",
    "December",
  ];
  if (!year || !month || !day || !months[month - 1]) return iso;
  return `${day} ${months[month - 1]} ${year}`;
}

function dogName(dog: DogStay): string {
  if (dog.unnamed || !dog.name) return "Unnamed";
  return dog.name;
}

function Pair({
  kicker,
  left,
  right,
  leftWho,
  rightWho,
  equal,
  hot,
  nLeft,
  nRight,
  verdict,
  gapMax,
}: {
  kicker: string;
  left: number;
  right: number;
  leftWho: string;
  rightWho: string;
  equal: boolean;
  hot?: boolean;
  nLeft: number;
  nRight: number;
  verdict: string;
  gapMax: number;
}) {
  const gap = Math.abs(left - right);
  return (
    <div className={hot ? styles.pairHot : styles.pair}>
      <p className={styles.pairKicker}>{kicker}</p>
      <p className={styles.nums}>
        <span className={hot ? styles.hurt : styles.quiet}>
          {formatDays(left)}
        </span>
        <span className={styles.sign} aria-hidden="true">
          {equal ? "=" : "≠"}
        </span>
        <span className={styles.quiet}>{formatDays(right)}</span>
        <span className={styles.visuallyHidden}>
          {equal ? "equals" : "does not equal"}
        </span>
      </p>
      <span
        className={styles.gap}
        style={{ width: `${Math.max((gap / gapMax) * 100, 3)}%` }}
        aria-hidden="true"
      />
      <p className={styles.who}>
        <span>{leftWho}</span>
        <span aria-hidden="true"> · </span>
        <span>{rightWho}</span>
      </p>
      <p className={styles.sample}>
        n = {nLeft.toLocaleString()} / {nRight.toLocaleString()}
      </p>
      <p className={styles.verdict}>{verdict}</p>
    </div>
  );
}

function Graphic({ coat, label }: { coat: FindingSplit; label: FindingSplit }) {
  const gapMax = Math.max(
    Math.abs(coat.med_yes - coat.med_no),
    Math.abs(label.med_yes - label.med_no),
    1,
  );
  return (
    <figure className={styles.graphic}>
      <figcaption className={styles.graphicCap}>
        One measure · median days to adoption · adults only
      </figcaption>
      <div className={styles.pairs}>
        <Pair
          kicker="The coat"
          left={coat.med_yes}
          right={coat.med_no}
          leftWho="black coat"
          rightWho="any other coat"
          equal
          nLeft={coat.n_yes}
          nRight={coat.n_no}
          verdict={`Same wait. ${formatP(coat.p)}.`}
          gapMax={gapMax}
        />
        <div className={styles.mid} aria-hidden="true" />
        <Pair
          kicker="The label"
          left={label.med_yes}
          right={label.med_no}
          leftWho="pit-bull staff mark"
          rightWho="no such mark"
          equal={false}
          hot
          nLeft={label.n_yes}
          nRight={label.n_no}
          verdict={`${formatDays(label.delta)} days longer. ${formatP(label.p)}.`}
          gapMax={gapMax}
        />
      </div>
      <p className={styles.readout}>
        The coat is not the wait. The label is.
      </p>
    </figure>
  );
}

export default async function PressPage() {
  const census = await getCensus();
  const coat = census.findings.black_adult;
  const label = census.findings.bully_adult;
  const dateline = formatDateline(census.as_of);
  const count = census.open_count.toLocaleString();

  return (
    <div className={`${styles.cover} ${serif.variable} ${sans.variable}`}>
      <header className={styles.folio}>
        <p className={styles.folioLeft}>
          <span>Investigation</span>
          <span aria-hidden="true"> · </span>
          <span>Austin Animal Center</span>
        </p>
        <p className={styles.folioMid}>Still in care · {dateline}</p>
        <p className={styles.folioRight}>
          <Link href="/explore" className={styles.back}>
            All looks
          </Link>
        </p>
      </header>

      <div className={styles.shell}>
        <main className={styles.stage} id="content" tabIndex={-1}>
          <p className={styles.kicker}>
            A public record of dogs who have not left · not a listing
          </p>
          <h1 className={styles.lede}>
            Still at
            <br />
            the shelter<span className={styles.period}>.</span>
          </h1>
          <p className={styles.deck}>
            You cannot adopt from this page.{" "}
            <strong>{count} dogs</strong> remain in care at Austin Animal
            Center. People blame a black coat. The files blame a staff label.
          </p>
          <Graphic coat={coat} label={label} />
          <p className={styles.colophon}>
            You cannot adopt here. These dogs are still at the shelter. This
            page does not place them, take applications, or send you home with
            one.
          </p>
        </main>

        <aside className={styles.rail} aria-labelledby="rail-heading">
          <div className={styles.railHead}>
            <h2 id="rail-heading" className={styles.railTitle}>
              Still inside
            </h2>
            <p className={styles.railLead}>
              {count} open stays. Days counted from intake. Not for checkout.
            </p>
          </div>
          <ul className={styles.list}>
            {census.dogs.map((dog) => (
              <li key={dog.stay_id}>
                <Link
                  href={`/dog/${encodeURIComponent(dog.stay_id)}`}
                  className={styles.row}
                  prefetch={false}
                >
                  <span className={styles.rowName}>{dogName(dog)}</span>
                  <span className={styles.rowDays}>
                    {dog.days_in_care}
                    <abbr title="days in care">d</abbr>
                  </span>
                  <span className={styles.rowMeta}>
                    <span
                      className={
                        dog.bully_label ? styles.tagHot : styles.tag
                      }
                    >
                      {dog.bully_label
                        ? "pit-bull label"
                        : "no pit-bull label"}
                    </span>
                    <span aria-hidden="true"> · </span>
                    <span>{dog.color || "coat unlisted"}</span>
                    <span aria-hidden="true"> · </span>
                    <span>
                      {dog.senior ? "senior" : dog.age_band || "age unlisted"}
                    </span>
                    <span aria-hidden="true"> · </span>
                    <span>{dog.breed || "breed unlisted"}</span>
                    <span aria-hidden="true"> · </span>
                    <span>in {dog.intake_date}</span>
                  </span>
                </Link>
              </li>
            ))}
          </ul>
          <p className={styles.railEnd}>
            End of the open list. You cannot adopt from this column. Austin
            Animal Center still holds every name above.
          </p>
        </aside>
      </div>
    </div>
  );
}
