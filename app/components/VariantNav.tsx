import Link from "next/link";

const VARIANTS = [
  { href: "/plain", id: "A", name: "Plain" },
  { href: "/story", id: "B", name: "Story" },
  { href: "/one", id: "C", name: "One dog" },
] as const;

export function VariantNav({ current }: { current: "A" | "B" | "C" | "hub" }) {
  return (
    <nav className="variant-nav" aria-label="Layout variants">
      <Link href="/" className={current === "hub" ? "is-current" : undefined}>
        Compare
      </Link>
      {VARIANTS.map((v) => (
        <Link
          key={v.id}
          href={v.href}
          className={current === v.id ? "is-current" : undefined}
          aria-current={current === v.id ? "page" : undefined}
        >
          {v.id} · {v.name}
        </Link>
      ))}
    </nav>
  );
}
