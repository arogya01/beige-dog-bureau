import type { Metadata } from "next";
import { Fragment_Mono, Oswald } from "next/font/google";

const oswald = Oswald({
  subsets: ["latin"],
  variable: "--font-oswald",
  display: "swap",
});

const fragmentMono = Fragment_Mono({
  weight: "400",
  subsets: ["latin"],
  variable: "--font-fragment",
  display: "swap",
});

export const metadata: Metadata = {
  title: "Departure board",
  description:
    "Dogs still in care at Austin Animal Center. No departures. You cannot adopt from this board.",
};

export default function ClockLayout({ children }: { children: React.ReactNode }) {
  return <div className={`${oswald.variable} ${fragmentMono.variable}`}>{children}</div>;
}
