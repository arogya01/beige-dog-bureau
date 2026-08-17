import { CompareBars } from "@/app/components/CompareBars";
import { Docket } from "@/app/components/Docket";
import { SiteChrome } from "@/app/components/SiteChrome";
import { getCensus } from "@/lib/census";

export const dynamic = "force-dynamic";

export default async function PlainPage() {
  const census = await getCensus();
  return (
    <SiteChrome
      current="A"
      note={`${census.open_count} dogs still in care as of ${census.as_of}.`}
    >
      <section aria-labelledby="plain-title">
        <p className="kicker">Variant A · say it plainly</p>
        <h1 className="story-title" id="plain-title">
          These dogs are still at the shelter.
        </h1>
        <p className="prose">
          This page ranks who has been waiting longest at Austin Animal Center.
          It is not a place to adopt. People often say black dogs wait longer.
          In {census.findings.cohort_n.toLocaleString()} adoptions, they do
          not. Adults staff labeled pit-bull type wait three times as long.
        </p>
        <CompareBars coat={census.findings.black_adult} label={census.findings.bully_adult} />
      </section>
      <Docket dogs={census.dogs} heading="Who is still waiting" />
    </SiteChrome>
  );
}
