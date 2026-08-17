import { loadSnapshot } from "./snapshot";
import { runSql, snowflakeConfigured } from "./snowflake";
import type { CensusPayload, DogStay } from "./types";

function rowToDog(r: string[]): DogStay {
  return {
    stay_id: r[0],
    animal_id: r[1],
    intake_date: r[2],
    days_in_care: Number(r[3]),
    name: r[4] || "",
    name_raw: r[5] || "",
    unnamed: r[6] === "true" || r[6] === "TRUE" || r[6] === "1",
    breed: r[7] || "",
    color: r[8] || "",
    sex: r[9] || "",
    source_name: r[10] || "",
    found_address: r[11] || "",
    age_years: r[12] ? Number(r[12]) : null,
    age_band: r[13] || "unknown",
    bully_label: r[14] === "true" || r[14] === "TRUE" || r[14] === "1",
    senior: r[13] === "senior",
    adult: r[13] === "adult",
    index: Number(r[15]),
    open: true,
    outcome_date: null,
    outcome_status: null,
  };
}

export async function getCensus(): Promise<CensusPayload> {
  const snap = loadSnapshot();
  if (!snowflakeConfigured()) return snap;
  try {
    const rows = await runSql(`
      SELECT stay_id, animal_id, TO_VARCHAR(intake_date), days_in_care,
             name, name_raw, unnamed, breed, color, sex, source_name,
             found_address, age_years, age_band, bully_label, index
      FROM CENSUS
      ORDER BY index DESC, days_in_care DESC
      LIMIT 800
    `);
    if (!rows.length) return snap;
    const dogs = rows.map(rowToDog);
    return {
      ...snap,
      source: "snowflake",
      open_count: dogs.length,
      dogs,
    };
  } catch {
    return snap;
  }
}

export async function getDog(stayId: string): Promise<{ dog: DogStay; census: CensusPayload } | null> {
  const census = await getCensus();
  const dog = census.dogs.find((d) => d.stay_id === stayId);
  if (!dog) return null;
  return { dog, census };
}

export function letterFromRow(dog: DogStay): string {
  const who = dog.name || `Unnamed, file ${dog.animal_id}`;
  const label = dog.bully_label ? "The breed field on this file carries a bully-type label." : "The breed field on this file does not carry a bully-type label.";
  const named = dog.unnamed ? "They arrived without a name." : "They arrived with a name.";
  return `${who} has been in care at Austin Animal Center for ${dog.days_in_care} days, since ${dog.intake_date}. Coat recorded as ${dog.color || "unknown"}. Breed recorded as ${dog.breed || "unknown"}. Age band ${dog.age_band}. ${named} ${label} The coat is not why this file is still open.`;
}
