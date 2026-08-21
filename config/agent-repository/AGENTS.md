# Pi Agent Evolution Repository Policy

## Purpose

This repository is the canonical source for reusable Pi extensions, skills,
and prompts. Runtime copies under `/home/pi/.pi-agent` are installed artifacts,
not source files.

Keep project-specific work in `/workspace`, Pi core changes in `/pi`, harness
changes in the `pi-evolving` repository, and reusable capabilities here.

## Before changing a capability

1. Identify the concrete task friction or explicit user request.
2. Read the relevant source and `agent.json`.
3. Run `git -C /agent status --short` and preserve unrelated changes.
4. Prefer the smallest reusable capability that resolves the problem.

## Manifest

Every installed regular file must be declared in `agent.json`. Supported types
are `extension`, `skill`, and `prompt`; source and target paths remain under
their matching `extensions/`, `skills/`, or `prompts/` directories.

Do not place credentials, sessions, tokens, downloaded models, generated
runtime state, or project-specific secrets in this repository.

## Candidate workflow

1. Make the focused source and manifest changes in `/agent`.
2. Run the narrowest relevant static checks or tests.
3. Install the deliberate candidate with
   `pi-agent-evolution install --working-tree`.
4. Run `/reload` in interactive Pi when necessary.
5. Exercise the capability against the motivating behavior.
6. Inspect the diff and retain or revise the candidate.
7. Commit accepted changes separately with a `capability:` prefix.

Never edit the installed `.pi-agent` copy as the canonical implementation.
Never bypass installer drift protection by overwriting runtime files manually.

## Git and remotes

A local Git repository is sufficient. A remote is optional. Never create a
remote, fetch, pull, force-push, or push automatically. A push is allowed only
after the user explicitly requests that external action.

Before finishing, inspect:

```bash
git -C /agent status --short
git -C /agent log -1 --oneline
git -C /agent branch --verbose --verbose
git -C /agent remote -v
```

Report the changed capability files, validation performed, commit hash, working
tree status, configured remotes, and whether committed work remains unpushed.
If no remote exists, say that the repository is local-only; do not treat that
as an error.
