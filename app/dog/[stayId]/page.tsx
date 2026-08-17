import Link from "next/link";
import { notFound } from "next/navigation";
import { LetterForm } from "@/app/components/LetterForm";
import { VariantNav } from "@/app/components/VariantNav";
import { getDog } from "@/lib/census";

export const dynamic = "force-dynamic";

export default async function CaseFilePage({
  params,
}: {
  params: Promise<{ stayId: string }>;
}) {
  const { stayId } = await params;
  const found = await getDog(decodeURIComponent(stayId));
  if (!found) notFound();
  const { dog, census } = found;

  return (
    <>
      <header className="masthead">
        <div className="wrap">
          <div className="masthead-top">
            <Link href="/plain">← Still waiting</Link>
            <span>File {dog.stay_id}</span>
            <span>{census.as_of}</span>
          </div>
          <VariantNav current="hub" />
        </div>
      </header>
      <main id="content" className="wrap" tabIndex={-1}>
        <article className="file">
          <div className="stamp">Still in care</div>
          <h1>{dog.name || "Unnamed"}</h1>
          <p className="meta">
            Animal {dog.animal_id} · intake {dog.intake_date} · {dog.days_in_care} days
          </p>
          <dl className="grid">
            <div className="field">
              <dt>Coat</dt>
              <dd>{dog.color || "Not recorded"}</dd>
            </div>
            <div className="field">
              <dt>Breed field</dt>
              <dd>{dog.breed || "Not recorded"}</dd>
            </div>
            <div className="field">
              <dt>Age band</dt>
              <dd>
                {dog.age_band}
                {dog.age_years != null ? ` · ${dog.age_years} yr` : ""}
              </dd>
            </div>
            <div className="field">
              <dt>Arrived named?</dt>
              <dd>{dog.unnamed ? "No" : "Yes"}</dd>
            </div>
            <div className="field">
              <dt>Bully-type label</dt>
              <dd>{dog.bully_label ? "Yes" : "No"}</dd>
            </div>
            <div className="field">
              <dt>Intake type</dt>
              <dd>{dog.source_name || "Not recorded"}</dd>
            </div>
            <div className="field">
              <dt>Found</dt>
              <dd>{dog.found_address || "Not recorded"}</dd>
            </div>
            <div className="field">
              <dt>Overlooked index</dt>
              <dd>{dog.index}</dd>
            </div>
          </dl>
          <p>
            <a href="https://data.austintexas.gov/Health-and-Community-Services/Austin-Animal-Center-Intakes/wter-evkm">
              Austin open data
            </a>
            . This page does not place a dog.
          </p>
          <LetterForm dog={dog} />
        </article>
      </main>
    </>
  );
}
