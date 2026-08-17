import Link from "next/link";
import { Docket } from "@/app/components/Docket";
import { SiteChrome } from "@/app/components/SiteChrome";
import { getCensus } from "@/lib/census";

export const dynamic = "force-dynamic";

export default async function OneDogPage() {
  const census = await getCensus();
  const dog = census.dogs[0];
  if (!dog) {
    return (
      <SiteChrome current="C">
        <p>No open stays in this snapshot.</p>
      </SiteChrome>
    );
  }
  const rest = census.dogs.slice(1);
  return (
    <SiteChrome current="C">
      <p className="kicker">Variant C · start with one dog</p>
      <div className="feature">
        <div>
          <h1 className="question">Why is {dog.name || "this dog"} still here after {dog.days_in_care} days?</h1>
          <p className="reveal">
            Coat listed as <em>{dog.color || "unlisted"}</em>. That is not the
            pattern in Austin. Adults with a bully-type <em>label</em> wait{" "}
            {census.findings.bully_adult.med_yes} days; other adults wait{" "}
            {census.findings.bully_adult.med_no}.{" "}
            {dog.bully_label
              ? "This file carries that label."
              : "This file does not carry that label — the long wait has another cause in the data."}
          </p>
          <p>
            <Link href={`/dog/${encodeURIComponent(dog.stay_id)}`}>
              Open {dog.name || "this"} full file
            </Link>
          </p>
        </div>
        <article className="file">
          <div className="stamp">Still in care</div>
          <h2>{dog.name || "Unnamed"}</h2>
          <p className="meta">
            {dog.days_in_care} days · {dog.breed} · in since {dog.intake_date}
          </p>
          <dl className="grid">
            <div className="field">
              <dt>Coat</dt>
              <dd>{dog.color || "Not recorded"}</dd>
            </div>
            <div className="field">
              <dt>Staff label</dt>
              <dd>{dog.bully_label ? "Pit-bull type" : "Not a bully-type label"}</dd>
            </div>
          </dl>
        </article>
      </div>
      <Docket dogs={rest} heading={`${rest.length} others still waiting`} />
    </SiteChrome>
  );
}
