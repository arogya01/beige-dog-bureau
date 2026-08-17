import type { Metadata } from "next";
import { Red_Hat_Mono, Red_Hat_Text } from "next/font/google";

const redHatText = Red_Hat_Text({
  subsets: ["latin"],
  weight: ["400", "500", "600", "700"],
  display: "swap",
  variable: "--font-clinic-text",
});

const redHatMono = Red_Hat_Mono({
  subsets: ["latin"],
  weight: ["400", "500", "600", "700"],
  display: "swap",
  variable: "--font-clinic-mono",
});

export const metadata: Metadata = {
  title: "Intake clipboard",
  description:
    "Admin census of dogs still in care at Austin Animal Center. Not a place to adopt.",
};

export default function ClinicLayout({ children }: { children: React.ReactNode }) {
  return (
    <div className={`${redHatText.variable} ${redHatMono.variable} ${redHatText.className}`}>
      {children}
    </div>
  );
}
