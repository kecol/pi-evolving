# Agent capability evolution

Reusable Pi behavior has its own Git history. Keep extensions, skills, and
prompts in the sibling `pi-agent-evolution` host repository, mount it at
`/agent`, and treat `/home/pi/.pi-agent` only as installed runtime state. A
local repository is complete and supported; adding a remote is optional.

## Default first setup

The default `.env` setting is relative to the harness repository:

```dotenv
PI_AGENT_EVOLUTION_PATH=../pi-agent-evolution
PI_AGENT_AUTO_INSTALL=1
```

On Linux, `~/gits/pi-evolving` therefore creates
`~/gits/pi-agent-evolution`. On Windows, `E:\codex\pi-evolving` creates
`E:\codex\pi-agent-evolution`. Absolute paths are also supported; an empty
value disables the feature.

Setup creates the directory only when it is absent or empty, initializes local
Git on `main`, seeds `AGENTS.md`, `README.md`, an empty `agent.json`, and the
three capability directories, then makes the initial commit. It never creates
a remote. Existing repositories are not overwritten.

## Adopt the existing goal extension

If the prototype repository is still named `pi-capabilities`, rename it and add
the manifest and governance policy:

```bash
mv ~/gits/pi-capabilities ~/gits/pi-agent-evolution
cd ~/gits/pi-agent-evolution
cp /path/to/pi-evolving/config/agent.example.json agent.json
cp /path/to/pi-evolving/config/agent-repository/AGENTS.md AGENTS.md
cp /path/to/pi-evolving/config/agent-repository/README.md README.md
git add AGENTS.md README.md agent.json
git commit -m "capability: add repository governance"
```

Its minimal structure is:

```text
pi-agent-evolution/
├── AGENTS.md
├── README.md
├── agent.json
├── extensions/
│   └── goal.ts
├── prompts/
└── skills/
```

The default relative path already resolves to this location when both
repositories are under `~/gits`. A custom absolute path also works:

```dotenv
PI_AGENT_EVOLUTION_PATH=/home/e/gits/pi-agent-evolution
PI_AGENT_AUTO_INSTALL=1
```

For PowerShell, use a Windows absolute path such as
`E:\gits\pi-agent-evolution`. The launcher bind-mounts it at `/agent`.

## Manifest

`agent.json` schema version 1 declares individual files:

```json
{
  "schemaVersion": 1,
  "capabilities": [
    {
      "type": "extension",
      "source": "extensions/goal.ts",
      "target": "extensions/goal.ts"
    }
  ]
}
```

Supported types are `extension`, `skill`, and `prompt`; both paths must remain
under the corresponding `extensions/`, `skills/`, or `prompts/` directory.
Version 1 installs regular files only and intentionally does not delete a
runtime file merely because it disappears from a newer manifest.

## Install and inspect

Committed state installs automatically during setup and immediately before
each Pi launch. You can also manage it explicitly:

```bash
./scripts/agent.sh status
./scripts/agent.sh install
./scripts/agent.sh history
```

```powershell
.\scripts\agent.ps1 status
.\scripts\agent.ps1 install
.\scripts\agent.ps1 history
```

Inside the Pi container, the equivalent executable is
`pi-agent-evolution`. After installing while interactive Pi is already
running, enter `/reload` to activate the new files.

Automatic installation requires a clean repository with at least one commit.
It validates paths, rejects symlinks, copies files atomically, and writes
`.pi-agent/agent.lock.json` with the source commit and SHA-256 hashes. If an
installed runtime file was edited independently, installation stops instead of
overwriting it.

## Test a candidate before committing

For an intentional dirty working tree:

```bash
./scripts/agent.sh install --working-tree
```

```powershell
.\scripts\agent.ps1 install -WorkingTree
```

Then use `/reload` and exercise the capability. If it passes, commit the source
in `/agent` with a focused message such as `capability: improve goal resume
handling`. If it fails, edit or restore the `/agent` candidate and install it
again. Startup never opts into a dirty candidate automatically.

`PI_AGENT_AUTO_INSTALL=0` disables installation during setup and Pi launch;
the explicit status/install/history commands remain available.
