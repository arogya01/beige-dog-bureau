"use client";

import { useState } from "react";
import type { DogStay } from "@/lib/types";

export function LetterForm({ dog }: { dog: DogStay }) {
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
    <form className="letter" onSubmit={onSubmit}>
      <h2>Letter from the file</h2>
      <label htmlFor="q">Question Cortex may answer only from this row</label>
      <textarea id="q" value={q} onChange={(e) => setQ(e.target.value)} required />
      <button type="submit" disabled={busy}>
        {busy ? "Writing…" : "Ask the warehouse"}
      </button>
      {err && (
        <p className="reply" role="alert">
          {err}
        </p>
      )}
      {letter && (
        <div className="reply" aria-live="polite">
          {letter}
        </div>
      )}
      {source && <pre className="source">{source}</pre>}
    </form>
  );
}
