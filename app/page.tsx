import type { Metadata } from "next";
import { DepartureBoard } from "@/app/components/DepartureBoard";
import { boardFontClass } from "@/app/components/boardFonts";

export const dynamic = "force-dynamic";

export const metadata: Metadata = {
  title: "No departures · Beige Dog Bureau",
  description:
    "Dogs still in care at Austin Animal Center. An all-black coat waits 34 days against 31 — the same. A bully-type staff label on an adult waits 62.5 against 26. The coat is not the wait. The label is.",
};

export default function HomePage() {
  return (
    <div className={boardFontClass}>
      <DepartureBoard />
    </div>
  );
}
