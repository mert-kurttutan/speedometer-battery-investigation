# Investigation rules

- Treat this repository as an evidence log. Separate measurements from hypotheses.
- This is a private repository and the user requested that raw captures be tracked in `captures/raw/`. Do not publish the repository or move these logs to a public location.
- Never change CPU power limits, MSRs, firmware settings, or thermal controls until measurements identify the active limit and the change has a safe rollback.
- Use repeatable runs with controlled power state, browser build, profile, display configuration, and background workload.
- Record each run's date, source (AC/battery), selected profile, browser/version, compositor, display, score, and relevant telemetry.
- Preserve failed and inconclusive tests, including command errors.

