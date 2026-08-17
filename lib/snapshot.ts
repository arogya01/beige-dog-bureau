import { readFileSync } from "node:fs";
import { join } from "node:path";
import type { CensusPayload } from "./types";

export function loadSnapshot(): CensusPayload {
  const path = join(process.cwd(), "out", "census.snapshot.json");
  return JSON.parse(readFileSync(path, "utf8")) as CensusPayload;
}
