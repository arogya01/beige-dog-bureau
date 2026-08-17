import type { Metadata } from "next";
import { Atkinson_Hyperlegible, Permanent_Marker } from "next/font/google";

const marker = Permanent_Marker({
  weight: "400",
  subsets: ["latin"],
  display: "swap",
  variable: "--font-board-marker",
});

const sans = Atkinson_Hyperlegible({
  weight: ["400", "700"],
  style: ["normal", "italic"],
  subsets: ["latin"],
  display: "swap",
  variable: "--font-board-sans",
});

export const metadata: Metadata = {
  title: "Kennel whiteboard",
  description:
    "Dogs still in the building at Austin Animal Center. Staff board, not an adoption site. You cannot adopt here.",
};

export default function BoardLayout({ children }: { children: React.ReactNode }) {
  return <div className={`${marker.variable} ${sans.variable}`}>{children}</div>;
}
