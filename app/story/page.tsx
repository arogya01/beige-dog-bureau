import { Docket } from "@/app/components/Docket";
import { SiteChrome } from "@/app/components/SiteChrome";
import { getCensus } from "@/lib/census";

export const dynamic = "force-dynamic";

export default async function StoryPage() {
  const census = await getCensus();
  const coat = census.findings.black_adult;
  const label = census.findings.bully_adult;
  return (
    <SiteChrome current="B" note="Read the three beats, then the list.">
      <p className="kicker">Variant B · a short story</p>
      <h1 className="story-title">Three facts, then the dogs.</h1>
      <ol className="beats">
        <li className="beat">
          <b>1 · The myth</b>
          <p>People say a black coat is why a dog waits.</p>
          <strong>Heard often</strong>
        </li>
        <li className="beat">
          <b>2 · The coat</b>
          <p>Austin adoptions, adults, black coat vs not.</p>
          <strong>
            {coat.med_yes} = {coat.med_no} days
          </strong>
        </li>
        <li className="beat beat--hot">
          <b>3 · The label</b>
          <p>Same city, adults staff marked as pit-bull type.</p>
          <strong>
            {label.med_yes} vs {label.med_no} days
          </strong>
        </li>
      </ol>
      <p className="prose">
        So the list below is not a cute gallery. It is who is still in care,
        with the pit-bull label called out because that is what the wait
        follows.
      </p>
      <Docket dogs={census.dogs} heading="Now the dogs still there" />
    </SiteChrome>
  );
}
