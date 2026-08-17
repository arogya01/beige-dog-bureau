"use client";

import Link from "next/link";
import { useMemo, useState } from "react";
import type { DogStay } from "@/lib/types";

const FILTERS = [
  { id: "all", label: "Everyone waiting" },
  { id: "unnamed", label: "Arrived unnamed" },
  { id: "bully", label: "Pit-bull label" },
  { id: "senior", label: "Seniors" },
  { id: "long", label: "Waiting 60+ days" },
] as const;

export function Docket({
  dogs,
  heading = "Still waiting",
}: {
  dogs: DogStay[];
  heading?: string;
}) {
  const [filter, setFilter] = useState<(typeof FILTERS)[number]["id"]>("all");
  const shown = useMemo(() => {
    return dogs.filter((d) => {
      if (filter === "unnamed") return d.unnamed;
      if (filter === "bully") return d.bully_label;
      if (filter === "senior") return d.senior;
      if (filter === "long") return d.days_in_care >= 60;
      return true;
    });
  }, [dogs, filter]);

  return (
    <section aria-labelledby="docket-heading">
      <div className="docket-head">
        <h2 id="docket-heading">{heading}</h2>
        <fieldset className="filters">
          <legend>Filter who is shown</legend>
          {FILTERS.map((f) => (
            <label key={f.id}>
              <input
                className="visually-hidden"
                type="radio"
                name="docket-filter"
                checked={filter === f.id}
                onChange={() => setFilter(f.id)}
              />
              {f.label}
            </label>
          ))}
        </fieldset>
      </div>
      <p className="banner" aria-live="polite">
        {shown.length} dogs. Sorted by who the data says is easiest to overlook —
        long stay, no name, pit-bull label, adult. Coat color is not used.
      </p>
      <ol className="docket">
        {shown.slice(0, 60).map((dog) => (
          <li key={dog.stay_id}>
            <Link className="row" href={`/dog/${encodeURIComponent(dog.stay_id)}`}>
              <span className="days">
                {dog.days_in_care}
                <i>days</i>
              </span>
              <span className="who">
                {dog.name || "Unnamed"}
                <small>
                  {dog.color || "No color listed"}
                  {dog.bully_label ? " · staff marked pit-bull type" : ` · ${dog.breed || "breed unknown"}`}
                </small>
              </span>
              <span className="chips">
                {dog.unnamed && <span className="chip">No name</span>}
                {dog.bully_label && <span className="chip chip--hot">Label</span>}
                {dog.senior && <span className="chip">Senior</span>}
              </span>
            </Link>
          </li>
        ))}
      </ol>
    </section>
  );
}
