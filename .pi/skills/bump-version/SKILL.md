---
name: bump-version
description: >-
  Bump TXS_VERSION in lib/config.sh with semantic versioning, commit as
  "chore(release): vX.Y.Z", and create a matching git tag. Use when the user
  says "release", "bump version", "new version", "cut a release", or invokes
  /bump-version.
---

# bump-version

Releases a new version of txs. Steps:

1. **Read current version** from `lib/config.sh` — find the `TXS_VERSION=` line.

2. **Determine bump type** — if the user did not specify (major / minor / patch), ask with `ask_user_question` before proceeding.

3. **Compute new version** by incrementing the appropriate segment and zeroing lower ones:
   - patch: `0.6.0` → `0.6.1`
   - minor: `0.6.0` → `0.7.0`
   - major: `0.6.0` → `1.0.0`

4. **Update `lib/config.sh`** — replace the `TXS_VERSION="..."` line with the new version. Edit only that line.

5. **Stage and commit**:
   ```bash
   git add lib/config.sh
   git commit -m "chore(release): v<NEW_VERSION>"
   ```

6. **Create annotated tag**:
   ```bash
   git tag -a "v<NEW_VERSION>" -m "v<NEW_VERSION>"
   ```

7. **Report** the new version, commit hash, and tag to the user.

## Rules

- Never bump without explicit confirmation of the bump type.
- Do not push — just commit and tag locally.
- Do not touch any file other than `lib/config.sh`.
- If the working tree has unstaged changes, warn the user before proceeding.
