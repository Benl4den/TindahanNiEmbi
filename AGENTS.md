# Project instructions

- Read [PROJECT_STATUS.md](PROJECT_STATUS.md) before planning work in this repository. Use it as a starting point, then verify relevant claims against current code, tests, and Git state.
- After every project change, update `PROJECT_STATUS.md` in the same work session. Refresh the review date, affected feature or issue statuses, evidence, and change log. Record verification and any material limitations. A tracker-only edit does not require a recursive change-log entry.
- Keep **implemented**, **partial/defect**, **not implemented**, and **recommendation** distinct. Do not turn an idea or an older conversation into an approved requirement without evidence.
- Identify local uncommitted work separately from committed behavior. Preserve existing user changes and avoid claiming a feature shipped solely because a file exists.
- The Android app supports both phone and tablet layouts. For UI changes, check the affected screen at a compact phone width and a tablet width, including the phone navigation and tablet sidebar when relevant. The shell currently switches at 900dp.
- When a previously listed gap is fixed, mark it resolved with the relevant code/test evidence instead of silently deleting it. Keep this file concise enough to serve as the project's current-status reference.
