/**
 * POST /api/ask - the Bureau's public reading room.
 *
 * TWO MODES, one endpoint.
 *
 *   mode "analyst" (default)  A visitor asks the census a question in plain
 *     English. Cortex Analyst writes SQL against semantic/census.yaml, we run
 *     that SQL against SHELTER.AAC, and we return THE GENERATED SQL ALONGSIDE
 *     THE ROWS. Publishing the SQL is the entire point: the visitor is invited
 *     to go looking for a coat-colour effect, read the query that looked for
 *     it, and watch it fail to appear. That is a proof they performed, not a
 *     claim we made.
 *
 *   mode "letter" (send a stay_id)  The original grounded case letter for one
 *     dog still in care. Kept alive, unchanged in contract, because
 *     app/components/LetterForm.tsx posts {stay_id, question} and expects
 *     {letter, source}.
 *
 * IRON RULE OBSERVED: there is not one statistic typed into this file. The
 * letter's grounding line is SELECTed from SHELTER.AAC.FINDINGS at request
 * time; if that query fails the line is omitted rather than guessed. The old
 * version of this route carried the string "black coat median 28 vs 28 (p=1).
 * Adult bully-label 91 vs 32" as a literal - every one of those five numbers
 * disagrees with the warehouse, which is exactly why hand-typed statistics
 * are banned here.
 *
 * NEVER A BLANK SCREEN: no PAT, a 429, a warehouse timeout or a refusal all
 * return HTTP 200 with an explanatory payload and the suggested questions, so
 * the page always has something to render.
 */

import { NextResponse } from "next/server";
import { getDog, letterFromRow } from "@/lib/census";
import {
  AnalystError,
  SUGGESTED_QUESTIONS,
  analystConfigured,
  analystModelSource,
  askAnalyst,
  type AnalystTurn,
} from "@/lib/analyst";
import {
  cortexComplete,
  runSqlWithColumns,
  snowflakeConfigured,
  type SqlResult,
} from "@/lib/snowflake";

export const dynamic = "force-dynamic";

const MAX_QUESTION = 500;
const MAX_ROWS = 200;

/* ================================================================== *
 * Entry point
 * ================================================================== */

export async function GET() {
  return NextResponse.json({
    modes: ["analyst", "letter"],
    analyst_available: analystConfigured(),
    semantic_model: analystModelSource(),
    warehouse: snowflakeConfigured() ? "SHELTER.AAC" : null,
    suggested_questions: SUGGESTED_QUESTIONS,
  });
}

export async function POST(req: Request) {
  let body: {
    question?: string;
    stay_id?: string;
    mode?: string;
    history?: AnalystTurn[];
  };
  try {
    body = await req.json();
  } catch {
    return NextResponse.json({ error: "Send a JSON body" }, { status: 400 });
  }

  const stayId = body.stay_id?.trim();
  const mode = body.mode?.trim() || (stayId ? "letter" : "analyst");

  if (mode === "letter") return letterMode(stayId, body.question);
  return analystMode(body.question, body.history);
}

/* ================================================================== *
 * Mode 1: ask the census
 * ================================================================== */

async function analystMode(rawQuestion?: string, history?: AnalystTurn[]) {
  const question = (rawQuestion || "").trim().slice(0, MAX_QUESTION);
  if (!question) {
    return NextResponse.json(
      { error: "Ask the census a question.", suggested_questions: SUGGESTED_QUESTIONS },
      { status: 400 },
    );
  }

  // No PAT, or the semantic model is not on disk. Render the room, say why it
  // is shut, and offer no numbers at all - a fabricated answer here would be
  // worse than an empty one.
  if (!analystConfigured()) {
    return NextResponse.json({
      mode: "analyst",
      question,
      available: false,
      via: "unavailable",
      answer:
        "The reading room needs a live connection to SHELTER.AAC to answer this, " +
        "and the Bureau cannot reach the warehouse right now. The bulletin and the " +
        "case files are still open, and they are served from the last census snapshot.",
      note: snowflakeConfigured()
        ? "semantic/census.yaml was not found and SNOWFLAKE_SEMANTIC_MODEL_FILE is unset"
        : "no Snowflake credentials configured",
      semantic_model: analystModelSource(),
      suggested_questions: SUGGESTED_QUESTIONS,
      sql: "",
      columns: [],
      rows: [],
      row_count: 0,
    });
  }

  // Step 1: Analyst writes the SQL. It never sees a row of data - only the
  // semantic model.
  let plan;
  try {
    plan = await askAnalyst(question, history || []);
  } catch (err) {
    return NextResponse.json(unavailable(question, err, "planning"));
  }

  // Analyst can decline: an ambiguous or out-of-scope question comes back with
  // no statement and a list of things it could answer instead. That refusal is
  // a legitimate answer and is passed through verbatim.
  if (!plan.sql) {
    return NextResponse.json({
      mode: "analyst",
      question,
      available: true,
      via: "cortex_analyst",
      answered: false,
      answer:
        plan.interpretation ||
        "The census cannot answer that from the columns it has. Try one of the suggestions.",
      interpretation: plan.interpretation,
      sql: "",
      columns: [],
      rows: [],
      row_count: 0,
      suggestions: plan.suggestions,
      suggested_questions: SUGGESTED_QUESTIONS,
      request_id: plan.request_id,
      warnings: plan.warnings,
      semantic_model: analystModelSource(),
      model_names: plan.model_names,
    });
  }

  // Step 2: we run the SQL ourselves against SHELTER.AAC.
  let result: SqlResult;
  try {
    result = await runSqlWithColumns(plan.sql, { maxRows: MAX_ROWS });
  } catch (err) {
    // The SQL is still worth publishing even when it would not execute - a
    // visitor can read it and judge it. Do not hide the query behind the error.
    return NextResponse.json({
      ...unavailable(question, err, "execution"),
      available: true,
      via: "cortex_analyst",
      answered: false,
      interpretation: plan.interpretation,
      sql: plan.sql,
      verified_query: plan.verified_query,
      request_id: plan.request_id,
    });
  }

  // Step 3: a sentence. The deterministic one is computed straight from the
  // returned cells and is always correct. The Cortex-written one reads better
  // and is allowed to fail; if it does, the deterministic one stands.
  const literal = describeRows(result);
  const narrative = await narrate(question, plan.interpretation, plan.sql, result);

  return NextResponse.json({
    mode: "analyst",
    question,
    available: true,
    answered: true,
    via: narrative ? "cortex_analyst+cortex_complete" : "cortex_analyst",
    answer: narrative || literal,
    answer_literal: literal,
    interpretation: plan.interpretation,
    sql: plan.sql,
    verified_query: plan.verified_query,
    columns: result.columns,
    rows: result.rows,
    row_count: result.rows.length,
    total_rows: result.total_rows,
    truncated: result.truncated,
    request_id: plan.request_id,
    warnings: plan.warnings,
    question_category: plan.question_category,
    model_names: plan.model_names,
    semantic_model: analystModelSource(),
    warehouse: "SHELTER.AAC",
    suggested_questions: SUGGESTED_QUESTIONS,
  });
}

/* ================================================================== *
 * Mode 2: the grounded case letter (original behaviour, preserved)
 * ================================================================== */

const LETTER_SYSTEM = `You write case letters for the Beige Dog Bureau.
You may use ONLY the JSON object provided. If a field is null or empty, say it is unknown.
Every number you write must appear verbatim in the JSON. Do not compute, round or estimate.
Do not invent a name, personality, medical diagnosis, home, or yard.
Do not advise adoption. Do not claim Black Dog Syndrome.
published_findings covers the whole adopted cohort, not this dog: cite it as context, never as this dog's prediction.
Never suggest coat colour affects how long a dog waits; in this data it does not, and the p-values in published_findings say so.
If the question needs a fact not in the JSON, refuse in one sentence.
Write the body of the letter only: no letterhead, no date line, no address block, no signature, and no square-bracket placeholders of any kind.
Keep the letter under 140 words.`;

async function letterMode(stayId?: string, rawQuestion?: string) {
  const question = (rawQuestion || "Write the case letter.").trim().slice(0, MAX_QUESTION);
  if (!stayId) {
    return NextResponse.json({ error: "stay_id is required" }, { status: 400 });
  }
  const found = await getDog(stayId);
  if (!found) {
    return NextResponse.json({ error: "No open file with that id" }, { status: 404 });
  }

  const row: Record<string, unknown> = {
    stay_id: found.dog.stay_id,
    animal_id: found.dog.animal_id,
    name: found.dog.name || null,
    days_in_care: found.dog.days_in_care,
    intake_date: found.dog.intake_date,
    color: found.dog.color || null,
    breed: found.dog.breed || null,
    age_band: found.dog.age_band,
    unnamed: found.dog.unnamed,
    bully_label: found.dog.bully_label,
    found_address: found.dog.found_address || null,
  };

  // The one piece of context the letter is allowed beyond the row: the
  // published findings, SELECTed live. Omitted entirely if the query fails -
  // never substituted with a remembered number.
  const findings = await publishedFindings();
  if (findings) row.published_findings = findings;

  const source = JSON.stringify(row, null, 2);

  if (!snowflakeConfigured()) {
    return NextResponse.json({
      mode: "letter",
      letter: letterFromRow(found.dog),
      source,
      via: "template",
    });
  }
  try {
    const letter = await cortexComplete(LETTER_SYSTEM, `${question}\n\nFILE:\n${source}`);
    return NextResponse.json({ mode: "letter", letter, source, via: "cortex" });
  } catch (err) {
    return NextResponse.json({
      mode: "letter",
      letter: letterFromRow(found.dog),
      source,
      via: "template",
      note: err instanceof Error ? err.message : "Cortex unavailable",
    });
  }
}

type PublishedFinding = {
  label: string;
  median_days_with: number;
  median_days_without: number;
  delta_days: number;
  p_value: number;
  n_with: number;
  n_without: number;
  cohort_n: number;
};

let findingsCache: { at: number; rows: PublishedFinding[] } | null = null;
const FINDINGS_TTL_MS = 10 * 60 * 1000;

/**
 * The seven published splits, read from SHELTER.AAC.FINDINGS.
 *
 * FINDINGS is rebuilt by sql/03_findings.sql from a real 5,000-permutation
 * test, so these are computed receipts rather than remembered ones. Cached for
 * ten minutes because the table changes only when that script is re-run.
 *
 * Returns null on any failure. A letter without the context line is correct;
 * a letter with a made-up context line is not.
 */
async function publishedFindings(): Promise<PublishedFinding[] | null> {
  if (!snowflakeConfigured()) return null;
  if (findingsCache && Date.now() - findingsCache.at < FINDINGS_TTL_MS) {
    return findingsCache.rows;
  }
  try {
    const res = await runSqlWithColumns(
      `SELECT label, med_yes, med_no, delta_days, p_value, n_yes, n_no, cohort_n
         FROM SHELTER.AAC.FINDINGS
        ORDER BY split_id`,
      { maxRows: 20 },
    );
    if (!res.rows.length) return null;
    const rows: PublishedFinding[] = res.rows.map((r) => ({
      label: r[0],
      median_days_with: Number(r[1]),
      median_days_without: Number(r[2]),
      delta_days: Number(r[3]),
      p_value: Number(r[4]),
      n_with: Number(r[5]),
      n_without: Number(r[6]),
      cohort_n: Number(r[7]),
    }));
    findingsCache = { at: Date.now(), rows };
    return rows;
  } catch {
    return null;
  }
}

/* ================================================================== *
 * Helpers
 * ================================================================== */

function unavailable(question: string, err: unknown, stage: "planning" | "execution") {
  const analystErr = err instanceof AnalystError ? err : null;
  const detail = err instanceof Error ? err.message : "the warehouse did not answer";
  const rateLimited = analystErr?.status === 429;

  return {
    mode: "analyst" as const,
    question,
    available: false,
    answered: false,
    via: "unavailable" as const,
    stage,
    answer: rateLimited
      ? "The reading room is busy - Snowflake is rate-limiting Cortex right now. " +
        "Give it a moment and ask again; the bulletin and the case files are unaffected."
      : "The Bureau could not put that question to the warehouse just now. " +
        "The bulletin and the case files are still open.",
    retryable: analystErr ? analystErr.retryable : true,
    note: detail,
    status: analystErr?.status,
    request_id: analystErr?.requestId,
    sql: "",
    columns: [] as string[],
    rows: [] as string[][],
    row_count: 0,
    semantic_model: analystModelSource(),
    suggested_questions: SUGGESTED_QUESTIONS,
  };
}

/**
 * A sentence built only from cells that came back. Never rounds, never
 * interprets, never adds a number that is not in the result set. This is the
 * floor the answer can never drop below.
 */
function describeRows(res: SqlResult): string {
  if (!res.rows.length) return "The query ran and matched no rows.";

  if (res.rows.length === 1) {
    const pairs = res.columns
      .map((c, i) => `${humanise(c)}: ${res.rows[0][i] ?? "unknown"}`)
      .join(" · ");
    return pairs;
  }

  const shown = res.truncated
    ? `${res.rows.length} of ${res.total_rows} rows`
    : `${res.rows.length} rows`;
  const first = res.columns.map((c, i) => `${humanise(c)} ${res.rows[0][i] ?? "unknown"}`).join(", ");
  return `${shown}, ${res.columns.length} columns. First row: ${first}.`;
}

function humanise(column: string): string {
  return column.toLowerCase().replace(/_/g, " ");
}

/**
 * Optional prose. Cortex sees the question, the SQL and the returned rows -
 * nothing else - and is told in the plainest terms available that it may not
 * introduce a number. If it errors, times out or is rate-limited we drop it
 * silently and the deterministic sentence is published instead.
 */
async function narrate(
  question: string,
  interpretation: string,
  sql: string,
  res: SqlResult,
): Promise<string | null> {
  if (!res.rows.length) return null;
  const table = [res.columns.join(" | "), ...res.rows.slice(0, 25).map((r) => r.join(" | "))].join(
    "\n",
  );
  const system = `You are the duty clerk of the Beige Dog Bureau, a civic gazette built on Austin Animal Center open data.
Answer the visitor's question in at most three sentences, using ONLY the result rows given to you.
Every number you write must appear verbatim in those rows. Do not compute, round, rescale or estimate anything.
If the rows do not answer the question, say exactly what is missing and stop.
Report a null result as a result: if a difference is small or a p-value is large, say plainly that the data cannot distinguish it from chance. Do not dress it up as a weak effect.
p-values here come from a 5,000-shuffle permutation test whose floor is 0.0002; never call one zero.
This is not an adoption service. Do not recommend a dog, do not describe a dog's temperament or health, and do not invent a name for a dog that has none.
Coat colour does not predict how long a dog waits in this data; the bully-type breed LABEL does. Keep those two straight.
No preamble, no sign-off, no markdown.`;
  const user = `VISITOR QUESTION: ${question}
HOW CORTEX ANALYST READ IT: ${interpretation}
SQL IT WROTE:
${sql}

RESULT ROWS:
${table}`;
  try {
    return (await cortexComplete(system, user)).trim() || null;
  } catch {
    return null;
  }
}
