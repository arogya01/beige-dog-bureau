let meta = #{
    name: "ui-design-variants",
    description: "Fan out four visually distinct first-screen designs for Beige Dog Bureau so a stranger can pick the most intuitive one",
    when_to_use: "When the gazette first screen is still hard to understand and you want parallel visual redesigns to compare live",
    phases: [
        #{ title: "Design", detail: "four isolated first screens" },
        #{ title: "Hub", detail: "wire the compare board" },
        #{ title: "Check", detail: "confirm they actually differ" },
    ],
};

fn common_rules() {
    let p = "";
    p += "PROJECT ROOT: /Users/arogyabichpuria/Documents/beige-dog-bureau\n";
    p += "This is a Next.js 15 / React 19 app. Dev server is already on http://localhost:3456.\n\n";
    p += "PRODUCT (do not change):\n";
    p += "- Public bulletin of dogs STILL IN CARE at Austin Animal Center.\n";
    p += "- NOT an adoption marketplace. No adopt/search/apply CTA.\n";
    p += "- Finding: black-coat adult median wait equals non-black (use census.findings.black_adult).\n";
    p += "- Finding: adults with a pit-bull staff label wait much longer (use census.findings.bully_adult).\n";
    p += "- Coat is NOT the wait. The label is.\n\n";
    p += "DATA: import { getCensus } from \"@/lib/census\". Call it in an async server component.\n";
    p += "export const dynamic = \"force-dynamic\";\n";
    p += "DogStay fields you will use: stay_id, name, unnamed, days_in_care, breed, color, bully_label, senior, age_band, intake_date.\n";
    p += "Link each dog to `/dog/${encodeURIComponent(dog.stay_id)}`.\n";
    p += "Footer or equivalent MUST say the visitor cannot adopt here.\n\n";
    p += "HARD RULES:\n";
    p += "1. Use read_file / grep / search_replace / write tools. Do not invent APIs from memory.\n";
    p += "2. Write ONLY inside your assigned folder. Do not edit lib/, app/globals.css, app/layout.tsx, app/plain, app/story, app/one, app/dog, app/components, or any other explore slug.\n";
    p += "3. Do NOT import SiteChrome, VariantNav, Docket, or CompareBars. Those are the gazette that failed the intuition test.\n";
    p += "4. Do NOT use Fraunces, Newsreader, IBM Plex Mono, beige paper, manila folders, brass, cabinet teal, or the words bureau / docket / overlooked index.\n";
    p += "5. Scope all styles with a CSS module (page.module.css) on a full-viewport wrapper. Do not leak selectors into body.\n";
    p += "6. Load fonts with next/font/google in your page or a local layout.tsx in YOUR folder only.\n";
    p += "7. A stranger who has never read the brief must understand, in five seconds, that these dogs are still at the shelter and this page is not Petfinder.\n";
    p += "8. Show both findings with the real numbers from getCensus(), plus a usable list of open dogs.\n";
    p += "9. Add a small text link back to /explore (label: All looks) — do not rebuild the old variant switcher.\n";
    p += "10. Keep it accessible: real headings, focus styles, contrast, no color-only meaning.\n";
    return p;
}

fn implement_prompt(slug, route, title, aesthetic, fonts, palette, layout, remember) {
    let p = "";
    p += "Implement ONE first-screen UI variant. You own only this route.\n\n";
    p += common_rules();
    p += "\nYOUR VARIANT\n";
    p += "slug: " + slug + "\n";
    p += "route: " + route + "\n";
    p += "title: " + title + "\n";
    p += "aesthetic: " + aesthetic + "\n";
    p += "fonts (locked): " + fonts + "\n";
    p += "palette (locked): " + palette + "\n";
    p += "layout (locked): " + layout + "\n";
    p += "the one thing to remember: " + remember + "\n\n";
    p += "FILES TO CREATE:\n";
    p += "- app/explore/" + slug + "/page.tsx\n";
    p += "- app/explore/" + slug + "/page.module.css\n";
    p += "Optional: app/explore/" + slug + "/layout.tsx if you need a font wrapper.\n\n";
    p += "Read lib/types.ts and lib/census.ts before coding. Then implement a complete, distinctive, production-grade first screen.\n";
    p += "Commit fully to this aesthetic. If it could be mistaken for the current gazette or for another explore variant, start over.\n";
    p += "When done, reply with: slug, route, and one sentence on what a stranger understands first.\n";
    return p;
}

let variants = [
    #{
        slug: "board",
        route: "/explore/board",
        title: "Kennel whiteboard",
        aesthetic: "A real municipal kennel whiteboard under fluorescent light. Dry-erase marker, scuffed linoleum, magnetic photo cards, leftover tape. Lived-in, not cute, not bureaucratic.",
        fonts: "next/font/google Permanent_Marker + Atkinson_Hyperlegible",
        palette: "linoleum #b7c4ae, board white #f7f7f4, marker blue #184a8c, marker red #c41e3a, fluorescent #fff6c8",
        layout: "A wall-mounted whiteboard is the page. Title STILL HERE in marker. Days-in-care are huge dry-erase numbers on cards. Findings live as two boxed notes taped to the corner of the board.",
        remember: "It looks like staff wrote who is still in the building.",
    },
    #{
        slug: "press",
        route: "/explore/press",
        title: "Investigation cover",
        aesthetic: "A dark investigative-magazine cover, closer to a longform news desk than a city gazette. Stark, quiet, one chart that hurts.",
        fonts: "next/font/google Cormorant_Garamond + Source_Sans_3",
        palette: "ink #0e1116, cream #f4efe4, hairline #3a3f47, chartreuse #d4ff4a, no teal, no beige",
        layout: "Full-bleed dark cover. One giant lede. Two compared numbers as a single graphic. Dogs run as a tight classifieds column on the right, not cards.",
        remember: "It is a story about a wait, not a gallery of pets.",
    },
    #{
        slug: "clock",
        route: "/explore/clock",
        title: "Departure board",
        aesthetic: "Transit departure board / split-flap clock. Time is the product. Amber on deep green-black. No paper, no folders.",
        fonts: "next/font/google Oswald + Fragment_Mono",
        palette: "board #07140f, flap #10241c, amber #ffb000, cream #e8dcc8, delayed red #ff4d2e",
        layout: "Hero is the longest wait as a huge split-flap number of days. Under it, a timetable of every open dog: name, destination=still here, delay=days. Findings are two rows: COAT on time, LABEL delayed.",
        remember: "The first thing you feel is how long they have been waiting.",
    },
    #{
        slug: "clinic",
        route: "/explore/clinic",
        title: "Intake clipboard",
        aesthetic: "Sterile municipal clinic, not a vintage office. Thermal-print type, one metal clipboard, mint wall, no manila romance.",
        fonts: "next/font/google Red_Hat_Text + Red_Hat_Mono",
        palette: "wall #d9ebe6, form #fbfaf6, ink #1c2430, rule #9aa7a3, alert #b42318",
        layout: "Hero is one filled intake form for the longest-wait dog, stamped NOT ADOPTABLE ON THIS SITE. Two lab-result strips for coat vs label. Remaining dogs are a stack of thinner intake slips.",
        remember: "This is an admin record of who is still in care.",
    },
];

phase("Design");
log("Four isolated first screens: board, press, clock, clinic");

let jobs = [];
for v in variants {
    jobs.push(#{
        prompt: implement_prompt(v.slug, v.route, v.title, v.aesthetic, v.fonts, v.palette, v.layout, v.remember),
        label: "design:" + v.slug,
        capability_mode: "read-write",
    });
}
let built = parallel(jobs);

let built_ok = 0;
for r in built {
    if r != () && r.success { built_ok += 1; }
}
log(built_ok.to_string() + "/4 design agents returned success");

phase("Hub");
let hub_prompt = "";
hub_prompt += "Update the compare surfaces so a human can open all four new looks.\n\n";
hub_prompt += common_rules();
hub_prompt += "\nYOU MAY EDIT ONLY:\n";
hub_prompt += "- app/explore/page.tsx (create)\n";
hub_prompt += "- app/explore/page.module.css (create if needed)\n";
hub_prompt += "- app/page.tsx (add one link or short section pointing at /explore — keep the existing A/B/C chooser working)\n\n";
hub_prompt += "Create /explore as a compare board for the four DESIGN variants, not the three copy variants:\n";
hub_prompt += "1. /explore/board — Kennel whiteboard\n";
hub_prompt += "2. /explore/press — Investigation cover\n";
hub_prompt += "3. /explore/clock — Departure board\n";
hub_prompt += "4. /explore/clinic — Intake clipboard\n\n";
hub_prompt += "Each card: one-line promise of what a stranger should understand, plus the route.\n";
hub_prompt += "Say clearly these four change LOOK and interaction, while /plain /story /one only changed copy.\n";
hub_prompt += "Read app/page.tsx first. Do not restyle the whole site. Do not touch other explore slugs.\n";
let hub = agent(hub_prompt, #{ label: "hub", capability_mode: "read-write" });
if hub == () || !hub.success {
    log("Hub agent failed; continuing to check files that exist");
}

phase("Check");
let check_prompt = "";
check_prompt += "Adversarially inspect the four new first screens. Use read_file and grep. Do not edit.\n\n";
check_prompt += "PROJECT ROOT: /Users/arogyabichpuria/Documents/beige-dog-bureau\n";
check_prompt += "Required files:\n";
check_prompt += "- app/explore/board/page.tsx + page.module.css\n";
check_prompt += "- app/explore/press/page.tsx + page.module.css\n";
check_prompt += "- app/explore/clock/page.tsx + page.module.css\n";
check_prompt += "- app/explore/clinic/page.tsx + page.module.css\n";
check_prompt += "- app/explore/page.tsx\n\n";
check_prompt += "For each slug, confirm ALL of these, with file evidence:\n";
check_prompt += "1. File exists and is a real page, not a placeholder.\n";
check_prompt += "2. Uses getCensus() and links dogs to /dog/[stayId].\n";
check_prompt += "3. Does not import SiteChrome, VariantNav, Docket, CompareBars.\n";
check_prompt += "4. Does not use Fraunces / Newsreader / IBM Plex Mono / bureau / docket.\n";
check_prompt += "5. Says the visitor cannot adopt here.\n";
check_prompt += "6. Surfaces both findings (coat vs label) from census data.\n";
check_prompt += "7. Visual system is actually distinct from the other three (fonts, color, layout).\n";
check_prompt += "8. First-screen copy would tell a stranger these dogs are still at the shelter.\n\n";
check_prompt += "Also check app/page.tsx still has working A/B/C links.\n";
check_prompt += "Write a short comparison a human can use to pick: which variant states intent fastest, which feels like Petfinder by accident, which should be the homepage.\n";
check_prompt += "Name a recommended default only if the evidence supports it; otherwise say they need to be seen live.\n";

let check = agent(check_prompt, #{
    label: "check",
    capability_mode: "read-only",
});

let report = "# UI design variants\n\n";
report += "Four first screens were requested, each with its own look.\n\n";
report += "- Kennel whiteboard: http://localhost:3456/explore/board\n";
report += "- Investigation cover: http://localhost:3456/explore/press\n";
report += "- Departure board: http://localhost:3456/explore/clock\n";
report += "- Intake clipboard: http://localhost:3456/explore/clinic\n";
report += "- Compare board: http://localhost:3456/explore\n\n";
report += "Design agents that returned success: " + built_ok.to_string() + " / 4\n";
if hub != () && hub.success {
    report += "Hub agent: success\n";
} else {
    report += "Hub agent: failed or empty\n";
}
report += "\n## Checker notes\n\n";
if check != () && check.success && check.output != () {
    report += check.output + "\n";
} else {
    report += "Checker did not return a usable report. Open the four URLs and judge live.\n";
}
let path = write_scratch_file("ui-design-variants.md", report);
complete(#{
    path: path,
    built_ok: built_ok,
    compare: "http://localhost:3456/explore",
});
