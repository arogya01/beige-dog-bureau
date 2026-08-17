import { readFileSync, existsSync } from "node:fs";
import { join } from "node:path";

function readEnvFile() {
  const path = join(process.cwd(), ".env.local");
  if (!existsSync(path)) return;
  for (const line of readFileSync(path, "utf8").split("\n")) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#") || !trimmed.includes("=")) continue;
    const eq = trimmed.indexOf("=");
    const key = trimmed.slice(0, eq).trim();
    const val = trimmed.slice(eq + 1).trim();
    if (!(key in process.env)) process.env[key] = val;
  }
}

readEnvFile();

export function snowflakeConfigured(): boolean {
  return Boolean(process.env.SNOWFLAKE_ACCOUNT && process.env.SNOWFLAKE_PAT);
}

function host(): string {
  const account = (process.env.SNOWFLAKE_ACCOUNT || "").replaceAll("_", "-");
  return `${account}.snowflakecomputing.com`;
}

export async function runSql(statement: string): Promise<string[][]> {
  const url = `https://${host()}/api/v2/statements`;
  const res = await fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Accept: "application/json",
      Authorization: `Bearer ${process.env.SNOWFLAKE_PAT}`,
      "X-Snowflake-Authorization-Token-Type": "PROGRAMMATIC_ACCESS_TOKEN",
    },
    body: JSON.stringify({
      statement,
      timeout: 60,
      warehouse: process.env.SNOWFLAKE_WAREHOUSE || "COMPUTE_WH",
      database: process.env.SNOWFLAKE_DATABASE || "SHELTER",
      schema: process.env.SNOWFLAKE_SCHEMA || "AAC",
      role: process.env.SNOWFLAKE_ROLE || "ACCOUNTADMIN",
    }),
  });
  const body = (await res.json()) as {
    data?: string[][];
    message?: string;
    code?: string;
    statementHandle?: string;
    resultSetMetaData?: { partitionInfo?: unknown[] };
  };
  if (!res.ok) {
    throw new Error(body.message || `Snowflake HTTP ${res.status}`);
  }
  const rows = body.data || [];
  // The API splits wide result sets across partitions and only inlines the
  // first. Reading just body.data silently truncates the census.
  const partitions = body.resultSetMetaData?.partitionInfo?.length ?? 1;
  for (let p = 1; p < partitions && body.statementHandle; p += 1) {
    const pRes = await fetch(`${url}/${body.statementHandle}?partition=${p}`, {
      method: "GET",
      headers: snowflakeHeaders(),
    });
    const pBody = (await pRes.json()) as { data?: string[][]; message?: string };
    if (!pRes.ok) throw new Error(pBody.message || `Snowflake HTTP ${pRes.status}`);
    rows.push(...(pBody.data || []));
  }
  return rows;
}

/* ------------------------------------------------------------------ *
 * Additive helpers (added for the Cortex Analyst path).
 * Nothing above this line was changed - other modules import runSql,
 * cortexComplete and snowflakeConfigured and must keep working.
 * ------------------------------------------------------------------ */

/** Fully-qualified Snowflake host, e.g. `abc-xy12345.snowflakecomputing.com`. */
export function snowflakeHost(): string {
  return host();
}

/** The three headers every Snowflake REST call in this app needs. */
export function snowflakeHeaders(): Record<string, string> {
  return {
    "Content-Type": "application/json",
    Accept: "application/json",
    Authorization: `Bearer ${process.env.SNOWFLAKE_PAT}`,
    "X-Snowflake-Authorization-Token-Type": "PROGRAMMATIC_ACCESS_TOKEN",
  };
}

export type SqlResult = {
  columns: string[];
  rows: string[][];
  truncated: boolean;
  total_rows: number;
};

type StatementBody = {
  data?: string[][];
  message?: string;
  code?: string;
  statementHandle?: string;
  resultSetMetaData?: {
    numRows?: number;
    rowType?: { name: string; type?: string }[];
  };
};

const MS_PER_DAY = 86_400_000;

/**
 * The SQL REST API does not send dates as dates. A DATE arrives as the number
 * of days since 1970-01-01 ("20231") and a TIMESTAMP as seconds with a
 * fractional part. Rendering those raw puts "20231" on a public page under the
 * heading "intake date", so the row type is used to put them back into ISO
 * form. Everything else is passed through byte-for-byte - no rounding, no
 * reformatting of numbers.
 */
function decodeCell(value: string | null, type?: string): string {
  if (value === null || value === undefined) return "";
  switch ((type || "").toLowerCase()) {
    case "date": {
      const days = Number(value);
      if (!Number.isFinite(days)) return value;
      return new Date(days * MS_PER_DAY).toISOString().slice(0, 10);
    }
    case "timestamp_ntz":
    case "timestamp_ltz":
    case "timestamp_tz": {
      const seconds = Number.parseFloat(value);
      if (!Number.isFinite(seconds)) return value;
      return new Date(seconds * 1000).toISOString().slice(0, 19).replace("T", " ");
    }
    default:
      return value;
  }
}

/**
 * Run one statement and return column names alongside the rows.
 *
 * Differs from runSql() in two ways that matter for Analyst-generated SQL:
 *
 *  1. It returns the column names. Analyst writes its own projection, so the
 *     caller cannot know the shape in advance and positional access is not
 *     an option.
 *  2. It polls the statement handle. Snowflake answers 202 with a
 *     `statementHandle` whenever execution outruns the inline timeout, and a
 *     naive reader treats that as an empty result set - a silent wrong
 *     answer rather than an error. Every published number on this site comes
 *     back through here, so a silent empty is the one failure mode we cannot
 *     tolerate.
 */
export async function runSqlWithColumns(
  statement: string,
  opts: { maxRows?: number; timeoutSeconds?: number; pollMs?: number } = {},
): Promise<SqlResult> {
  const maxRows = opts.maxRows ?? 200;
  const base = `https://${host()}/api/v2/statements`;
  const headers = snowflakeHeaders();

  let res = await fetch(base, {
    method: "POST",
    headers,
    body: JSON.stringify({
      statement,
      timeout: opts.timeoutSeconds ?? 60,
      warehouse: process.env.SNOWFLAKE_WAREHOUSE || "COMPUTE_WH",
      database: process.env.SNOWFLAKE_DATABASE || "SHELTER",
      schema: process.env.SNOWFLAKE_SCHEMA || "AAC",
      role: process.env.SNOWFLAKE_ROLE || "ACCOUNTADMIN",
    }),
  });
  let body = (await res.json()) as StatementBody;
  if (!res.ok) throw new Error(body.message || `Snowflake HTTP ${res.status}`);

  const handle = body.statementHandle;
  for (let i = 0; body.data === undefined && handle && i < 40; i += 1) {
    await new Promise((r) => setTimeout(r, opts.pollMs ?? 1500));
    res = await fetch(`${base}/${handle}`, { method: "GET", headers });
    body = (await res.json()) as StatementBody;
    if (!res.ok) throw new Error(body.message || `Snowflake HTTP ${res.status}`);
  }
  if (body.data === undefined) {
    throw new Error("Snowflake did not finish the statement in time");
  }

  const rowType = body.resultSetMetaData?.rowType || [];
  const columns = rowType.map((c) => c.name);
  const all = body.data || [];
  return {
    columns,
    rows: all.slice(0, maxRows).map((row) => row.map((cell, i) => decodeCell(cell, rowType[i]?.type))),
    truncated: all.length > maxRows,
    total_rows: body.resultSetMetaData?.numRows ?? all.length,
  };
}

export async function cortexComplete(system: string, user: string): Promise<string> {
  const url = `https://${host()}/api/v2/cortex/v1/chat/completions`;
  const res = await fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Accept: "application/json",
      Authorization: `Bearer ${process.env.SNOWFLAKE_PAT}`,
    },
    body: JSON.stringify({
      model: process.env.SNOWFLAKE_CORTEX_MODEL || "llama3.1-70b",
      messages: [
        { role: "system", content: system },
        { role: "user", content: user },
      ],
      max_completion_tokens: 400,
    }),
  });
  const body = (await res.json()) as {
    choices?: { message?: { content?: string } }[];
    message?: string;
  };
  if (!res.ok) {
    throw new Error(body.message || `Cortex HTTP ${res.status}`);
  }
  const text = body.choices?.[0]?.message?.content;
  if (!text) throw new Error("Cortex returned an empty letter");
  return text;
}
