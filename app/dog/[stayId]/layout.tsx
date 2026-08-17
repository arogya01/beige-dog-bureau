import type { Metadata } from "next";
import { boardFontClass } from "@/app/components/boardFonts";

export const metadata: Metadata = {
  title: "Case file · Beige Dog Bureau",
  description:
    "One dog still in care at Austin Animal Center, read from the warehouse row. The coat is not the wait. The label is.",
};

export default function CaseFileLayout({ children }: { children: React.ReactNode }) {
  return <div className={boardFontClass}>{children}</div>;
}
