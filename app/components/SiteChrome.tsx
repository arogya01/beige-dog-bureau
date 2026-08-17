import { VariantNav } from "./VariantNav";

export function SiteChrome({
  current,
  children,
  note,
}: {
  current: "A" | "B" | "C" | "hub";
  children: React.ReactNode;
  note?: string;
}) {
  return (
    <>
      <header className="masthead">
        <div className="wrap">
          <div className="masthead-top">
            <span>Austin Animal Center · not an adoption site</span>
            <span>Beige Dog Bureau</span>
          </div>
          <VariantNav current={current} />
          {note && <p className="banner">{note}</p>}
        </div>
      </header>
      <main id="content" className="wrap" tabIndex={-1}>
        {children}
      </main>
      <footer className="site-foot">
        <div className="wrap">
          Public Austin data. You cannot adopt a dog here. We only show who is
          still waiting, and what the numbers say about why.
        </div>
      </footer>
    </>
  );
}
