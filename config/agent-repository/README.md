# Pi Agent Evolution

This repository is the canonical source for reusable Pi capabilities. The
Pi Evolving harness mounts it at `/agent` and installs files declared in
`agent.json` into Pi's persistent runtime state.

## Structure

- `extensions/` contains Pi extensions.
- `skills/` contains skills and their supporting files.
- `prompts/` contains reusable prompts.
- `agent.json` declares the regular files installed into `.pi-agent`.
- `AGENTS.md` defines the development, testing, and Git workflow.

This repository works entirely locally. A Git remote is optional and is never
created or pushed by setup.
