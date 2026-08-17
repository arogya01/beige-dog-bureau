import type { FindingSplit } from "@/lib/types";

export function CompareBars({
  coat,
  label,
}: {
  coat: FindingSplit;
  label: FindingSplit;
}) {
  const max = Math.max(coat.med_yes, coat.med_no, label.med_yes, label.med_no, 1);
  return (
    <div className="compare">
      <figure>
        <figcaption>What people blame: the coat</figcaption>
        <Bar n={coat.med_yes} max={max} note="Black coat" />
        <Bar n={coat.med_no} max={max} note="Any other coat" />
        <p>Same wait. {coat.med_yes} days vs {coat.med_no}.</p>
      </figure>
      <figure className="compare--alert">
        <figcaption>What the data blames: the label</figcaption>
        <Bar n={label.med_yes} max={max} note="Adult, pit-bull label" hot />
        <Bar n={label.med_no} max={max} note="Adult, no such label" />
        <p>
          Triple the wait. {label.med_yes} days vs {label.med_no}.
        </p>
      </figure>
    </div>
  );
}

function Bar({
  n,
  max,
  note,
  hot,
}: {
  n: number;
  max: number;
  note: string;
  hot?: boolean;
}) {
  return (
    <div className="bar-row">
      <span className="bar-note">{note}</span>
      <span className="bar-track">
        <span
          className={hot ? "bar-fill bar-fill--hot" : "bar-fill"}
          style={{ width: `${(n / max) * 100}%` }}
        />
      </span>
      <span className="bar-n">{n}</span>
    </div>
  );
}
