import Link from "next/link";

export default function NotFound() {
  return (
    <main id="content" className="wrap" tabIndex={-1}>
      <h1>No such file</h1>
      <p>That stay is not on the open docket.</p>
      <p>
        <Link href="/">Return to the bulletin</Link>
      </p>
    </main>
  );
}
