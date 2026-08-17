import type { Metadata } from "next";
import { boardFontClass } from "@/app/components/boardFonts";

export const metadata: Metadata = {
  title: "Departure board",
  description:
    "Dogs still in care at Austin Animal Center. No departures. You cannot adopt from this board.",
};

export default function ClockLayout({ children }: { children: React.ReactNode }) {
  return <div className={boardFontClass}>{children}</div>;
}
