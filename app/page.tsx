import Link from "next/link";
import { SiteChrome } from "@/app/components/SiteChrome";

export default function HubPage() {
  return (
    <SiteChrome current="hub">
      <p className="kicker">Pick a first screen</p>
      <h1 className="story-title">Same bulletin. Three ways in.</h1>
      <p className="prose">
        All three use the same Austin data and the same ranking. They only
        change how fast a stranger understands what this is. Open each, then
        come back.
      </p>
      <div className="chooser">
        <Link className="choice" href="/plain">
          <b>A</b>
          <h2>Plain</h2>
          <p>One sentence, two bars, then the waiting list. Fastest to scan.</p>
        </Link>
        <Link className="choice" href="/story">
          <b>B</b>
          <h2>Story</h2>
          <p>Myth, then the coat, then the label. The list comes last.</p>
        </Link>
        <Link className="choice" href="/one">
          <b>C</b>
          <h2>One dog</h2>
          <p>Start on the longest wait. Ask why. Then show everyone else.</p>
        </Link>
      </div>
    </SiteChrome>
  );
}
