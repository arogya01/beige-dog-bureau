/**
 * Cortex Analyst client for the Beige Dog Bureau.
 *
 * WHAT THIS IS. Snowflake Cortex Analyst turns a plain-English question into
 * SQL against a semantic model, and hands back the SQL it wrote. It does not
 * see the data - only the model in semantic/census.yaml. We then execute that
 * SQL ourselves and publish the SQL text next to the rows.
 *
 * WHY IT MATTERS HERE. The Bureau's whole claim is "look at the receipts".
 * A language model writing prose about a dog proves nothing; a visitor typing
 * "do black dogs wait longer?", reading the generated SQL, and watching a
 * one-day difference come back out of 2,821 real adoptions proves the thesis
 * without taking our word for anything. Showing the SQL is not a debug
 * affordance, it is the product.
 *
 * MODEL DELIVERY. Two supported paths, both live and tested:
 *   inline  - the repo file is POSTed as `semantic_model` (default; the repo
 *             stays the single source of truth, no deploy step to forget)
 *   stage   - `semantic_model_file` points at @SHELTER.AAC.SEMANTIC/census.yaml
 *             (set SNOWFLAKE_SEMANTIC_MODEL_FILE; publish with
 *             scripts/publish_semantic_model.py)
 *
 * NOTHING IN THIS FILE HARDCODES A STATISTIC. It moves questions in and SQL
 * out. Every number the visitor sees is produced by executing that SQL.
 */

import { readFileSync, existsSync } from "node:fs";
import { join } from "node:path";
import { CORTEX_TIMEOUT_MS, snowflakeConfigured, snowflakeHeaders, snowflakeHost } from "./snowflake";

export const SEMANTIC_MODEL_PATH = join(process.cwd(), "semantic", "census.yaml");

/** Questions the bulletin offers as a starting point. */
export const SUGGESTED_QUESTIONS = [
  "Do black dogs wait longer?",
  "Which dogs have waited the longest?",
  "Does the pit bull label matter more for adults?",
  "How many dogs are still in care?",
  "Are pit bulls more likely to be returned after adoption?",
  "Which breeds count as bully-type?",
] as const;

export class AnalystError extends Error {
  readonly status: number;
  readonly requestId?: string;

  constructor(message: string, status: number, requestId?: string) {
    super(message);
    this.name = "AnalystError";
    this.status = status;
    this.requestId = requestId;
  }

  /** Rate limited or the warehouse is busy - worth telling the visitor to retry. */
  get retryable(): boolean {
    return this.status === 429 || this.status === 503 || this.status >= 500;
  }
}

export type AnalystAnswer = {
  /** Analyst's restatement of the question - how it understood the ask. */
  interpretation: string;
  /** The SQL it wrote. Empty when it declined to answer. */
  sql: string;
  /** Name of the curated verified query it matched, if any. */
  verified_query?: string;
  /** Follow-up questions Analyst offers when it cannot answer. */
  suggestions: string[];
  request_id?: string;
  warnings: string[];
  /** e.g. CLEAR_SQL when it produced SQL confidently. */
  question_category?: string;
  model_names: string[];
};

type AnalystContent = {
  type: string;
  text?: string;
  statement?: string;
  suggestions?: string[];
  confidence?: { verified_query_used?: { name?: string } | null } | null;
};

type AnalystBody = {
  message?: { content?: AnalystContent[] };
  request_id?: string;
  warnings?: { message?: string }[];
  response_metadata?: { model_names?: string[]; question_category?: string };
  message_text?: string;
  error_code?: string;
};

let cachedModel: string | null = null;

/**
 * The semantic model YAML, read from the repo and memoised.
 *
 * Kept out of the request path deliberately: this file is ~57KB of carefully
 * worded description, and re-reading it per question is pointless I/O. It is
 * cached per process, so editing the YAML needs a dev-server reload.
 */
export function loadSemanticModel(): string | null {
  if (cachedModel !== null) return cachedModel;
  if (!existsSync(SEMANTIC_MODEL_PATH)) return null;
  cachedModel = readFileSync(SEMANTIC_MODEL_PATH, "utf8");
  return cachedModel;
}

/** Stage path form, when the operator prefers the warehouse copy. */
export function semanticModelFile(): string | null {
  const file = process.env.SNOWFLAKE_SEMANTIC_MODEL_FILE?.trim();
  return file ? file : null;
}

/** True when a question can actually be sent: PAT present and a model to send. */
export function analystConfigured(): boolean {
  if (!snowflakeConfigured()) return false;
  return Boolean(semanticModelFile() || loadSemanticModel());
}

/** Which delivery path a call would take. Surfaced to the visitor as provenance. */
export function analystModelSource(): "stage" | "inline" | "missing" {
  if (semanticModelFile()) return "stage";
  if (loadSemanticModel()) return "inline";
  return "missing";
}

export type AnalystTurn = { role: "user" | "analyst"; text: string };

/**
 * Ask Cortex Analyst a question. Returns the SQL it wrote; does NOT run it.
 *
 * Execution is left to the caller so that the generated SQL can be shown to
 * the visitor before, and independently of, any rows. If the SQL is wrong the
 * visitor should be able to see that it is wrong.
 */
export async function askAnalyst(
  question: string,
  history: AnalystTurn[] = [],
): Promise<AnalystAnswer> {
  const file = semanticModelFile();
  const model = file ? null : loadSemanticModel();
  if (!file && !model) {
    throw new AnalystError(
      "No semantic model: expected semantic/census.yaml or SNOWFLAKE_SEMANTIC_MODEL_FILE",
      500,
    );
  }

  // Analyst wants alternating turns; we pass at most a short tail so a long
  // session cannot push the semantic model out of the context window.
  const messages = [...history.slice(-6), { role: "user" as const, text: question }].map((t) => ({
    role: t.role,
    content: [{ type: "text", text: t.text }],
  }));

  const res = await fetch(`https://${snowflakeHost()}/api/v2/cortex/analyst/message`, {
    method: "POST",
    signal: AbortSignal.timeout(CORTEX_TIMEOUT_MS),
    headers: snowflakeHeaders(),
    body: JSON.stringify(
      file ? { messages, semantic_model_file: file } : { messages, semantic_model: model },
    ),
  });

  let body: AnalystBody;
  try {
    body = (await res.json()) as AnalystBody;
  } catch {
    throw new AnalystError(`Cortex Analyst HTTP ${res.status}`, res.status);
  }

  if (!res.ok) {
    throw new AnalystError(
      body.message_text || body.error_code || `Cortex Analyst HTTP ${res.status}`,
      res.status,
      body.request_id,
    );
  }

  const content = body.message?.content || [];
  const texts: string[] = [];
  let sql = "";
  let verified: string | undefined;
  let suggestions: string[] = [];

  for (const part of content) {
    if (part.type === "text" && part.text) texts.push(part.text);
    if (part.type === "sql" && part.statement) {
      sql = cleanSql(part.statement);
      verified = part.confidence?.verified_query_used?.name || undefined;
    }
    if (part.type === "suggestions" && part.suggestions) suggestions = part.suggestions;
  }

  return {
    interpretation: tidyInterpretation(texts.join("\n\n")),
    sql,
    verified_query: verified,
    suggestions,
    request_id: body.request_id,
    warnings: (body.warnings || []).map((w) => w.message || "").filter(Boolean),
    question_category: body.response_metadata?.question_category,
    model_names: body.response_metadata?.model_names || [],
  };
}

/**
 * Analyst appends a request-id comment and a trailing semicolon to every
 * statement. The comment is genuine provenance and worth keeping, but a
 * trailing `;` breaks the single-statement SQL REST endpoint, so it goes.
 */
function cleanSql(statement: string): string {
  return statement.trim().replace(/;\s*$/, "").trim();
}

/**
 * Analyst prefixes its restatement with a fixed preamble. The restatement is
 * useful - it shows how the question was read - but the preamble is noise on
 * a page that already says "this is our reading of your question".
 */
function tidyInterpretation(text: string): string {
  return text.replace(/^This is our interpretation of your question:\s*/i, "").trim();
}
