import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "It's Not the Coat · Beige Dog Bureau",
  description:
    "A public bulletin from Austin Animal Center open data. The coat is not the wait. The label is.",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <head>
        <link rel="preconnect" href="https://fonts.googleapis.com" />
        <link rel="preconnect" href="https://fonts.gstatic.com" crossOrigin="" />
        <link
          href="https://fonts.googleapis.com/css2?family=Fraunces:opsz,wght@9..144,500;9..144,600;9..144,700&family=IBM+Plex+Mono:wght@400;500;600&family=Newsreader:ital,opsz,wght@0,6..72,400;0,6..72,500;1,6..72,400&display=swap"
          rel="stylesheet"
        />
      </head>
      <body>
        <a className="skip-link visually-hidden" href="#content">
          Skip to content
        </a>
        {children}
      </body>
    </html>
  );
}
