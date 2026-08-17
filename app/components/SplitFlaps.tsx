import styles from "@/app/explore/clock/page.module.css";

/**
 * The split-flap day counter. Shared by the departure board and the single
 * case file so the number a reader sees in the "Delay" column is rendered by
 * the same code, in the same type, when they click through to the dog.
 */
export function SplitFlaps({ days }: { days: number }) {
  const whole = Math.max(0, Math.round(days));
  const digits = String(whole)
    .padStart(whole >= 1000 ? 4 : 3, "0")
    .split("");

  return (
    <div className={styles.flaps} data-count={digits.length} aria-hidden="true">
      {digits.map((digit, i) => (
        <span className={styles.flap} key={`${digit}-${i}`}>
          <span className={styles.flapTop} />
          <span className={styles.flapSplit} />
          <span className={styles.flapChar}>{digit}</span>
        </span>
      ))}
    </div>
  );
}
