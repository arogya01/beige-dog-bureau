import { Fragment_Mono, Oswald } from "next/font/google";

/**
 * Shared by every surface that renders the board: the front door (/),
 * /explore/clock, and /dog/[stayId]. A route that renders board CSS without
 * this class silently falls back to Arial Narrow, which is how the case file
 * ended up looking like a different site.
 */
export const oswald = Oswald({
  subsets: ["latin"],
  variable: "--font-oswald",
  display: "swap",
});

export const fragmentMono = Fragment_Mono({
  weight: "400",
  subsets: ["latin"],
  variable: "--font-fragment",
  display: "swap",
});

export const boardFontClass = `${oswald.variable} ${fragmentMono.variable}`;
