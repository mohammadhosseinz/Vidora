# Contributing

Read README.md and docs/BUILD.md. Keep downloads local, execute engines with argv lists (never user-built shell commands), scope cookie jars to the selected site and preserve temporary-file cleanup on cancellation/failure.

Translate user-visible strings into all four supported languages. Never add mandatory payment or send video URLs/cookies/files to an application backend.

Before proposing changes, run formatting, flutter analyze and relevant flutter tests. Explain the problem, changed behavior and validation. Do not include real cookies, private links, downloaded media or credentials in reports, commits or test fixtures. Runtime binaries and build outputs belong outside Git.
