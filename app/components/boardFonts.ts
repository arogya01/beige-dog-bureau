import { Fragment_Mono, Oswald } from "next/font/google";

/** Shared by the front door (/) and /explore/clock — both render the board. */
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
