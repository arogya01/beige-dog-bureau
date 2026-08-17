"use client";

import { useState } from "react";
import type { DogStay } from "@/lib/types";

/**
 * Class names supplied by the host page. The form carries no styling of its
 * own so the case file can dress it in the departure board's CSS module
 * without a second copy of this component existing to drift out of sync.
 */
export type LetterFormUi = {
  form?: string;
  label?: string;
  reply?: string;
  source?: string;
};

export function LetterForm({ dog, ui }: { dog: DogStay; ui: LetterFormUi }) {
  const [q, setQ] = useState("Write the case letter.");
  const [letter, setLetter] = useState("");
  const [source, setSource] = useState("");
  const [err, setErr] = useState("");
  const [busy, setBusy] = useState(false);

  async function onSubmit(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    setErr("");
    try {
      const res = await fetch("/api/ask", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ stay_id: dog.stay_id, question: q }),
      });
      const data = (await res.json()) as { letter?: string; source?: string; error?: string };
      if (!res.ok) throw new Error(data.error || "The bureau could not write.");
      setLetter(data.letter || "");
      setSource(data.source || "");
    } catch (ex) {
      setErr(ex instanceof Error ? ex.message : "The bureau could not write.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <form className={ui.form} onSubmit={onSubmit}>
      <label className={ui.label} htmlFor="q">
        Question Cortex may answer only from this row
      </label>
      <textarea id="q" value={q} onChange={(e) => setQ(e.target.value)} required />
      <button type="submit" disabled={busy}>
        {busy ? "Writing…" : "Ask the warehouse"}
      </button>
      {err && (
        <p className={ui.reply} role="alert">
          {err}
        </p>
      )}
      {letter && (
        <div className={ui.reply} aria-live="polite">
          {letter}
        </div>
      )}
      {source && <pre className={ui.source}>{source}</pre>}
    </form>
  );
}
