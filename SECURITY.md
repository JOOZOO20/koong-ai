# Security Policy — koong-agent

koong installs hooks that execute shell on every session start and every Bash call, plus pre-approved permissions. That makes koong itself a high-value target: we treat the harness as attack surface and document the threat model honestly.

## Threat model & mitigations

### 1. Supply-chain compromise of koong-agent (npm)

*An attacker who publishes a malicious koong version owns every session of every user who updates.*

- **Zero runtime dependencies** — the CLI uses Node stdlib only. There is no transitive dependency surface. CI fails if `dependencies` ever appears in package.json.
- **Provenance publishing** — releases are published from GitHub Actions with `npm publish --provenance`: npm cryptographically attests the package was built from this public repository at a specific commit. Verify with `npm audit signatures` or on the npm package page.
- **Auditable-invariant CI**: every file in `templates/claude/koong/scripts/` must be plain, readable bash with **no network calls** (`curl`, `wget`, `nc`, `/dev/tcp`) and **no obfuscated execution** (`eval`, piped `base64 -d`). CI greps for violations and fails the build. If a future version's hooks contact the network, that is a red flag by definition.
- Maintainer accounts use npm 2FA; publishing rights are limited to CI.
- **Official package name: `koong-agent`** (bin: `koong`). Anything else is not us — check the provenance attestation, not the name.

### 2. Prompt injection amplified by pre-approved permissions

*A malicious repository (README, code comments, issue text) instructs the agent, which holds auto-approved git/gh/build permissions.*

- **Network tools are never on the allowlist.** `curl`/`wget`/`nc`/`ssh`/`scp` always require human approval. This is a permanent invariant.
- **`git push` is restricted to `origin`** by the gate — pushing to any other remote or a direct URL is blocked, closing the main code-exfiltration path.
- `gh` is limited to `issue create/list`, `pr create/view`, `auth status` — no `gh api`, no `gh repo delete`.
- Committing secrets and staging `.env` are deterministically blocked; `gh repo create --public` is always blocked.
- Beginner mode additionally blocks `curl | bash` idioms and destructive commands.
- **Honest limit**: running a build IS arbitrary code execution (`build.gradle`, npm scripts, `conftest.py` all execute code). koong cannot change that. **Install koong only in repositories you trust as much as you trust running `npm install` in them.** That is the trust model, stated plainly.

### 3. Harness tampering inside an installed project

*A malicious PR or another agent edits `.claude/settings.json` or the gate scripts to disable enforcement.*

- Agents cannot Write/Edit/Bash-modify harness files (gate scripts, settings.json, koong agent/skill definitions) — hook-blocked; humans only. Agent model changes go through the audited `set-model.sh`.
- Agents cannot write to the state directory or loop-log — evidence forgery is identity-checked (`agent_type` from the hook input) and path-blocked.
- Any change touching `.claude/`, `CLAUDE.md`, or `.koong/` is automatically classified risk tier T3 (maximum review).
- `npx koong-agent doctor` performs an **integrity check**: installed enforcement files are compared against install-time SHA-256 hashes in the manifest; tampering is reported with a restore path.

### 4. Typosquatting

Cannot be fully prevented. Mitigations: this document names the official package; provenance attestation ties the package to this repository; the README badge links the verified publish chain.

## What koong does NOT do

- No telemetry, no phone-home, no network calls of its own. `loop-log.jsonl` stays in your repository.
- No credential handling: koong never reads or stores your tokens; `gh`/`git` use your existing local auth.

## Reporting a vulnerability

Open a GitHub Security Advisory on this repository (preferred) or email the maintainer. Please do not open public issues for exploitable problems. You can expect an initial response within 72 hours.
