# Build Brief: `pi-evolving`

## Purpose of this document

You are a local coding agent. Your task is to create a complete repository named
`pi-evolving` that makes it easy for other users to run an **evolving Pi coding
agent** inside Docker.

The intended user experience is deliberately small:

### Windows PowerShell

```powershell
git clone <pi-evolving-repository-url>
cd pi-evolving

.\setup.ps1
.\pi.ps1 C:\work\my-project
```

### Linux / WSL2

```bash
git clone <pi-evolving-repository-url>
cd pi-evolving

./setup.sh
./pi.sh ~/work/my-project
```

Everything else should be hidden behind scripts, Docker Compose, sensible
defaults, and clear documentation.

The repository must remain inspectable and understandable. Do not replace
simple scripts with a large application unless there is a clear reason.

---

# 1. High-level idea

We want to run the `earendil-works/pi` coding agent **from source** inside
Docker, while allowing Pi to inspect, modify, test, and commit changes to its
own source code.

Most self-evolution should be caused by **real task pressure**:

```text
real project/task
    ↓
observed friction
    ↓
candidate adaptation
    ↓
test/evaluate
    ↓
retain or revert
    ↓
continue task
```

The goal is **not** to constantly ask Pi to "improve itself."

Instead:

> Give Pi useful work. Give it access to its own implementation. Let repeated
> friction motivate focused changes.

---

# 2. Core architecture

The runtime must separate four domains:

```text
/workspace
    current project/job/task

/pi
    Pi's own source repository

/home/pi/.pi-agent
    Pi runtime state

/evolution
    lineage metadata, measurements, experiment records
```

Recommended persistence model:

```text
Docker image
    immutable-ish execution substrate

pi-source Docker volume
    mounted at /pi
    Pi source + .git + node_modules + build outputs

pi-agent-state Docker volume
    mounted at /home/pi/.pi-agent
    settings + sessions + auth metadata + downloaded tools

pi-evolution-state Docker volume
    mounted at /evolution
    generation metadata + baseline records + evaluation outputs

workspace bind mount
    mounted at /workspace
    current user project
```

Conceptually:

```text
                 ┌───────────────────────────┐
                 │     Docker substrate      │
                 │                           │
                 │ Node / npm                │
                 │ Git                       │
                 │ uv                        │
                 │ compilers/build tools     │
                 │ common Unix utilities     │
                 └─────────────┬─────────────┘
                               │
           ┌───────────────────┼───────────────────┐
           │                   │                   │
           ▼                   ▼                   ▼
       /workspace             /pi          ~/.pi-agent
       project/task         Pi source       runtime state
           │                   │                   │
           │                   ▼                   ▼
           │              Git lineage       acquired tools
           │
           ▼
      task pressure
           │
           ▼
       evolution
           │
           ▼
      /evolution
```

---

# 3. Why Pi itself must NOT be baked into the image

Do not make this the canonical installation:

```dockerfile
RUN npm install -g --ignore-scripts @earendil-works/pi-coding-agent
```

That would put Pi inside the Docker image.

If Pi changed or updated itself inside a disposable container, those changes
could disappear when the container is removed.

Instead, Pi's canonical implementation must be a persistent Git checkout
stored in `pi-source:/pi`.

Pi should run from source via:

```text
/pi/pi-test.sh
```

The upstream Pi repository documents this development workflow:

```bash
npm install --ignore-scripts
npm run build
npm run build:offline
npm run check
./test.sh
./pi-test.sh
```

The evolving system should use those upstream development mechanisms rather
than inventing a separate packaging path.

---

# 4. Why `/pi` should use a Linux-native Docker volume

Do not store the evolving `/pi` checkout on a Windows filesystem bind mount by
default.

During initial experiments under Docker Desktop + WSL2, placing `/pi` on a
Windows-backed bind mount caused problems with:

```text
chmod
npm install
Vite/Vitest temporary files
Unix permission tests
Git ownership semantics
file watchers
```

In particular, a fresh `npm install --ignore-scripts` failed with an error like:

```text
EPERM: operation not permitted, chmod ...
```

A Linux-native Docker named volume solved this class of problems.

Therefore the default architecture must use:

```text
pi-source:/pi
```

rather than:

```text
C:\...\pi-src:/pi
```

Advanced users may choose a WSL2/Linux filesystem bind mount later, but the
default should be robust.

---

# 5. Generation 0 substrate

The Docker image should be deliberately **small but generative**.

It should contain tools that allow Pi to acquire, build, inspect, and test new
capabilities.

The image should include:

```text
Node 24
npm
uv / uvx
Git
bash
curl
ca-certificates
ripgrep
jq
file
tree
less
build-essential
pkg-config
cmake
ninja-build
procps
lsof
iproute2
netcat-openbsd
rsync
sqlite3
zip
unzip
openssh-client
tini
```

Pi currently also needs native image/text libraries during builds:

```text
libcairo2-dev
libgif-dev
libjpeg-dev
libpango1.0-dev
librsvg2-dev
```

Do not preinstall every possible project dependency.

Do NOT include by default:

```text
numpy
pandas
PyTorch
Rust
Go
Java
DuckDB
Postgres
browser automation stacks
project-specific CLIs
```

The principle is:

> Generation 0 should provide capability acquisition mechanisms, not every
> future capability.

---

# 6. `fd` handling

Do not install Debian's `fd-find` package in Generation 0.

An older Debian `fd` caused Pi's `find` tests to fail because it did not support:

```text
--no-require-git
```

Pi already knows how to acquire a compatible `fd`.

In the working setup, Pi downloaded:

```text
fd 10.4.2
```

to:

```text
/home/pi/.pi-agent/bin/fd
```

Therefore the image should set:

```dockerfile
ENV PATH="/home/pi/.pi-agent/bin:${PATH}"
```

This gives Pi a persistent user-level executable directory.

The `pi-agent-state` volume makes acquired tools survive container recreation.

---

# 7. Non-root execution

Pi must run as a normal Unix user.

Do not run the evolving agent as root.

The image should create something like:

```text
user: pi
uid: 1001
gid: 1001
home: /home/pi
```

Make UID/GID configurable at build time:

```dockerfile
ARG PI_UID=1001
ARG PI_GID=1001
```

Running as root previously caused permission-sensitive tests to behave
incorrectly, because root could write files that were intentionally made
read-only.

The normal runtime user must therefore be:

```dockerfile
USER pi
```

---

# 8. Use `tini`

Use `tini` as PID 1.

Suggested entrypoint:

```dockerfile
ENTRYPOINT ["tini", "--", "/pi/pi-test.sh"]
```

Pi may later spawn:

```text
test runners
local servers
candidate successor agents
evaluators
child processes
```

A small init process makes signal propagation and process reaping cleaner.

---

# 9. Recommended Dockerfile

Create:

```text
docker/Dockerfile
```

Suggested content:

```dockerfile
FROM ghcr.io/astral-sh/uv:latest AS uv

FROM node:24-bookworm-slim

ARG PI_UID=1001
ARG PI_GID=1001

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    bash \
    build-essential \
    ca-certificates \
    cmake \
    curl \
    file \
    git \
    iproute2 \
    jq \
    less \
    libcairo2-dev \
    libgif-dev \
    libjpeg-dev \
    libpango1.0-dev \
    librsvg2-dev \
    lsof \
    netcat-openbsd \
    ninja-build \
    openssh-client \
    pkg-config \
    procps \
    ripgrep \
    rsync \
    sqlite3 \
    tini \
    tree \
    unzip \
    zip \
  && rm -rf /var/lib/apt/lists/*

COPY --from=uv /uv /uvx /usr/local/bin/

RUN groupadd --gid "${PI_GID}" pi \
  && useradd \
       --uid "${PI_UID}" \
       --gid "${PI_GID}" \
       --create-home \
       --shell /bin/bash \
       pi \
  && mkdir -p \
       /workspace \
       /pi \
       /evolution \
       /home/pi/.pi-agent \
  && chown -R pi:pi \
       /workspace \
       /pi \
       /evolution \
       /home/pi

RUN git config --system --add safe.directory /pi

ENV HOME=/home/pi
ENV PI_CODING_AGENT_DIR=/home/pi/.pi-agent
ENV PATH="/home/pi/.pi-agent/bin:${PATH}"

USER pi

WORKDIR /workspace

ENTRYPOINT ["tini", "--", "/pi/pi-test.sh"]
```

You may adjust details if upstream Pi changes require it, but keep the same
architectural principles.

---

# 10. Repository to create

Create a repository approximately like this:

```text
pi-evolving/
│
├── README.md
├── LICENSE
├── .gitignore
├── .env.example
├── compose.yaml
│
├── docker/
│   └── Dockerfile
│
├── config/
│   └── AGENTS.md
│
├── scripts/
│   ├── common.sh
│   ├── common.ps1
│   ├── setup.sh
│   ├── setup.ps1
│   ├── run.sh
│   ├── run.ps1
│   ├── shell.sh
│   ├── shell.ps1
│   ├── test.sh
│   ├── test.ps1
│   ├── history.sh
│   ├── history.ps1
│   ├── update.sh
│   ├── update.ps1
│   ├── reset.sh
│   └── reset.ps1
│
├── setup.sh
├── setup.ps1
├── pi.sh
├── pi.ps1
├── shell.sh
├── shell.ps1
├── test.sh
├── test.ps1
│
└── docs/
    ├── ARCHITECTURE.md
    ├── SETUP.md
    ├── EVOLUTION.md
    ├── TROUBLESHOOTING.md
    └── GENERATION_0.md
```

The root scripts can either contain the implementation or be thin wrappers
around `scripts/...`.

Prefer thin wrappers if it improves organization.

---

# 11. User-facing command surface

A normal user should only need a few commands.

## Bootstrap

Windows:

```powershell
.\setup.ps1
```

Linux / WSL2:

```bash
./setup.sh
```

## Run Pi against a project

Windows:

```powershell
.\pi.ps1 C:\work\my-project
```

Linux / WSL2:

```bash
./pi.sh ~/work/my-project
```

## Open a shell

```powershell
.\shell.ps1
```

or:

```bash
./shell.sh
```

## Test current Pi generation

```powershell
.\test.ps1
```

or:

```bash
./test.sh
```

## Inspect evolution history

```powershell
.\scripts\history.ps1
```

or:

```bash
./scripts/history.sh
```

## Fetch upstream changes

```powershell
.\scripts\update.ps1
```

or:

```bash
./scripts/update.sh
```

The important constraint:

> Users should not need to remember raw `docker run` invocations for normal
> use.

---

# 12. `setup` responsibilities

`setup.sh` and `setup.ps1` are the most important scripts.

They must be **idempotent**.

Running setup twice must not destroy:

```text
Pi self-changes
Git history
runtime state
sessions
downloaded tools
generation metadata
```

The setup flow should be:

```text
check Docker
    ↓
build image
    ↓
create named volumes if missing
    ↓
initialize volume ownership if needed
    ↓
clone Pi into pi-source if absent
    ↓
create evolve branch if absent
    ↓
configure Git identity if absent
    ↓
npm install --ignore-scripts if needed
    ↓
npm run build
    ↓
npm run check
    ↓
install/update global evolution instructions
    ↓
ensure fd can be acquired
    ↓
record generation-0 metadata if no generation exists
    ↓
print concise next steps
```

Do not automatically reset or overwrite an existing Pi lineage.

---

# 13. Detect Docker availability

`setup` should fail early with a useful error if Docker is unavailable.

Check something equivalent to:

```bash
docker version
```

Avoid assuming Docker Desktop specifically.

Support:

```text
Docker Desktop on Windows
Docker from WSL2
native Linux Docker
```

---

# 14. Named volumes

Use predictable names.

Recommended:

```text
pi-evolving-source
pi-evolving-agent-state
pi-evolving-evolution-state
```

or Compose-prefixed equivalents.

The scripts must avoid depending on Compose's project-name-generated volume
names unless the project name is explicitly fixed.

A clean approach is to declare external-style explicit names in `compose.yaml`,
for example:

```yaml
volumes:
  pi-source:
    name: pi-evolving-source
  pi-agent-state:
    name: pi-evolving-agent-state
  pi-evolution-state:
    name: pi-evolving-evolution-state
```

Use whichever approach is simplest and predictable.

---

# 15. `compose.yaml`

Create a Compose file representing the persistent architecture.

Suggested direction:

```yaml
services:
  pi:
    build:
      context: .
      dockerfile: docker/Dockerfile

    image: pi-evolving:local

    stdin_open: true
    tty: true

    environment:
      PI_SKIP_VERSION_CHECK: "1"

    volumes:
      - pi-source:/pi
      - pi-agent-state:/home/pi/.pi-agent
      - pi-evolution-state:/evolution

volumes:
  pi-source:
    name: pi-evolving-source

  pi-agent-state:
    name: pi-evolving-agent-state

  pi-evolution-state:
    name: pi-evolving-evolution-state
```

Do not hard-code `/workspace` here if doing so makes it difficult to mount an
arbitrary project.

It is acceptable for launcher scripts to use `docker run` directly while
Compose is used for image/volume definitions.

Choose the simplest coherent design.

---

# 16. Clone Pi into the source volume

On first setup, clone:

```text
https://github.com/earendil-works/pi.git
```

into:

```text
/pi
```

inside `pi-source`.

Then create:

```text
evolve
```

branch.

Example:

```bash
git clone https://github.com/earendil-works/pi.git /pi
cd /pi
git switch -c evolve
```

If `/pi/.git` already exists:

- do not reclone;
- do not reset;
- do not overwrite;
- inspect the current branch;
- preserve user changes.

---

# 17. Git model

Use:

```text
origin/main
    upstream Pi

evolve
    local evolutionary lineage
```

The normal self-modification branch is:

```text
evolve
```

Do not encourage Pi to directly modify `origin/main`.

Self-change commits should look like:

```text
evolve: improve large-file structural inspection
evolve: add persistent repository structure cache
evolve: reduce redundant file reads
```

---

# 18. Git identity

Configure a local repository identity if the user has not configured one.

Suggested default:

```text
user.name = Pi Evolving Agent
user.email = pi-evolving@local
```

Do this only in `/pi`, not globally on the user's host.

Let environment variables or `.env` override the defaults later.

---

# 19. `.env.example`

Create a small configuration file.

Suggested:

```env
PI_PROVIDER=llamacpp-wsl
PI_MODEL=local-coder

PI_HOST_PORT=9191
PI_CONTAINER_PORT=9191

PI_GIT_NAME=Pi Evolving Agent
PI_GIT_EMAIL=pi-evolving@local

PI_IMAGE=pi-evolving:local
```

Do not include credentials.

If `.env` is absent, `setup` may copy `.env.example` to `.env`.

The README should explain that users may need to change provider/model values.

---

# 20. Workspace launcher behavior

`pi.sh <workspace>` and `pi.ps1 <workspace>` should:

1. resolve the supplied path to an absolute host path;
2. verify the directory exists;
3. mount it at `/workspace`;
4. mount the three persistent volumes;
5. expose the configured port;
6. start Pi from `/pi/pi-test.sh`;
7. pass configured provider/model values;
8. preserve extra CLI arguments supplied after the workspace argument.

Example:

```bash
./pi.sh ~/work/actors --some-pi-flag value
```

should conceptually become:

```text
/pi/pi-test.sh
    --provider ...
    --model ...
    --some-pi-flag value
```

Do not hard-code only one possible Pi invocation.

---

# 21. PowerShell details

PowerShell uses the backtick for line continuation:

```powershell
docker run --rm -it `
  ...
```

Do not generate Bash-style `\` continuation in PowerShell scripts/docs.

When mounting paths, handle spaces correctly.

Prefer arrays/splatting over building giant command strings when practical.

For example, a PowerShell script can construct:

```powershell
$args = @(
  "run",
  "--rm",
  "-it",
  ...
)

docker @args
```

This is safer than complex quoting.

---

# 22. Bash details

Use:

```bash
set -euo pipefail
```

where reasonable.

Quote all workspace paths:

```bash
-v "$workspace:/workspace"
```

Resolve canonical paths carefully.

On Linux, prefer:

```bash
realpath
```

but do not assume macOS compatibility unless intentionally supported.

Primary targets are:

```text
Linux
WSL2
Windows PowerShell
```

---

# 23. Runtime state

Mount:

```text
pi-agent-state
```

at:

```text
/home/pi/.pi-agent
```

Set:

```text
HOME=/home/pi
PI_CODING_AGENT_DIR=/home/pi/.pi-agent
PATH=/home/pi/.pi-agent/bin:...
```

This stores things such as:

```text
settings.json
models.json / model store data
sessions
auth metadata
downloaded tools
fd
```

Do not commit these into `/pi`.

Do not copy secrets into the harness repository.

---

# 24. Global evolution instructions

The harness repository must contain:

```text
config/AGENTS.md
```

During setup, copy/synchronize this file into the persistent Pi runtime state in
the location Pi uses for global agent instructions.

If current Pi expects:

```text
/home/pi/.pi-agent/AGENTS.md
```

place it there.

Do not silently overwrite a user's customized version without a strategy.

A sensible approach:

```text
/home/pi/.pi-agent/AGENTS.md
    managed evolution policy
```

and perhaps retain:

```text
/home/pi/.pi-agent/AGENTS.local.md
```

for future user customization if Pi's loading behavior supports it.

For Generation 0, simplicity is more important than elaborate merging.

---

# 25. Initial evolution policy

Use the following as the initial `config/AGENTS.md`.

---

## BEGIN `config/AGENTS.md`

```markdown
# Evolving Pi Agent Policy

## Primary objective

Your primary objective is the task, job, project, or investigation under
`/workspace`.

Do not treat self-modification as the primary task unless explicitly asked.

## Your own implementation

Your own Pi source repository is available at:

`/pi`

It is a persistent Git repository.

The expected local evolution branch is:

`evolve`

You may inspect `/pi` whenever understanding your own implementation helps you
solve the current task.

You may modify `/pi` when concrete friction observed during useful work gives a
clear reason to do so.

## What counts as useful evolution

Prefer the smallest layer that solves the recurring limitation.

A useful ordering is:

1. Solve the current project directly.
2. Improve a project-local workflow or helper.
3. Create reusable instructions, a skill, extension, or tool.
4. Improve Pi's harness or general workflow.
5. Modify Pi core source when the limitation actually belongs there.
6. Propose an environment/Docker change when a missing system capability is
   broadly useful.

Do not modify Pi core merely because modifying Pi is possible.

## Task-induced pressure

Before modifying `/pi`, identify:

- the concrete friction observed during the current work;
- why it is likely to recur;
- what capability is missing or inefficient;
- what measurable or observable improvement you expect.

Prefer changes motivated by real work over abstract "make myself better"
changes.

## Self-modification workflow

When changing `/pi`:

1. Inspect the relevant implementation before editing.
2. Check `git status`.
3. Keep the change focused.
4. Build or run the narrowest relevant tests first.
5. Run `npm run check` for source changes.
6. Run broader tests when the change has broad impact.
7. Compare failures with the known Generation 0 baseline.
8. Inspect `git diff`.
9. Commit the self-change separately.
10. Use a commit message beginning with `evolve:`.
11. Continue the original project task.

Example:

`evolve: improve large-file structural inspection`

Do not mix project changes under `/workspace` with Pi self-changes under `/pi`
in the same Git commit.

## Current process versus next generation

Editing Pi's source does not retroactively change code already loaded by the
currently running Pi process.

Think in generations:

`Pi_n -> edits source -> tests candidate -> restart -> Pi_(n+1)`

After a self-change, restart Pi when necessary to evaluate the new generation.

Changes in `packages/coding-agent/src` may be picked up by the next
`/pi/pi-test.sh` launch directly from source.

Changes to shared monorepo packages may require rebuilding before the next
generation:

`npm run build`

## Git discipline

Treat `origin/main` as upstream Pi.

Treat `evolve` as the local evolutionary lineage.

Do not blindly overwrite local evolution with an upstream package update.

For upstream integration, prefer:

`git fetch origin`

followed by inspection and then an intentional rebase or merge.

Keep self-evolution commits small enough that upstream changes can be
reconciled later.

## Tests and baseline

Do not edit tests merely to erase an environment-specific baseline failure.

On the original Docker Desktop/WSL2 Generation 0 setup, Pi v0.84.2 had two
known clipboard failures caused by WSL detection from `/proc/version`.

A new failure beyond the recorded baseline is potentially a regression.

A previously failing baseline test becoming green is interesting and should be
understood rather than automatically accepted.

## Environment evolution

The container normally runs as the non-root `pi` user.

Do not assume `apt-get` is available during ordinary work.

For task-local Python dependencies, prefer project-local uv environments.

For reusable user-level executables, `/home/pi/.pi-agent/bin` is persistent
and already on PATH.

If a system package or system library would be broadly useful, propose or edit
the harness Dockerfile rather than treating an ephemeral installation as
permanent evolution.

The running container is not given the Docker socket by default, so changing
the Dockerfile describes the next environment generation but does not rebuild
the host image automatically.

## Secrets and runtime state

Runtime state belongs under:

`/home/pi/.pi-agent`

Do not commit auth material, credentials, tokens, or runtime session state into
`/pi`.

## Evolution criterion

The strongest reason to retain a self-change is evidence that it makes useful
work easier, faster, more reliable, more legible, or more capable.

The preferred loop is:

task
-> observed friction
-> candidate adaptation
-> test/evaluation
-> retain or revert
-> continue task

Self-modification without task pressure is a weaker signal than adaptation
caused by real work.
```

## END `config/AGENTS.md`

---

# 26. Preserve project-specific instructions

The global evolution policy must not replace project-level instructions.

A mounted project may contain its own:

```text
/workspace/AGENTS.md
```

Pi should receive both:

```text
global evolution policy
    +
project-local policy
```

Document this clearly.

---

# 27. Build and test Pi during setup

First install:

```bash
cd /pi
npm install --ignore-scripts
```

Then:

```bash
npm run build
npm run check
```

The scripts should print meaningful phases, for example:

```text
[1/8] Checking Docker
[2/8] Building substrate
[3/8] Creating persistent volumes
[4/8] Initializing Pi source
[5/8] Installing dependencies
[6/8] Building Pi
[7/8] Running checks
[8/8] Installing evolution policy
```

Avoid dumping unnecessary implementation noise when a concise status line is
enough.

Still let underlying errors remain visible.

---

# 28. Generation 0 test baseline

After setup, users should be able to run:

```bash
./test.sh
```

or:

```powershell
.\test.ps1
```

The test script should:

```text
verify fd is available
run npm run check
run ./test.sh inside /pi
capture summary
record baseline / comparison metadata
```

Do not make setup necessarily run the entire test suite every time if it is
expensive.

A reasonable split:

```text
setup:
    build + npm run check

test:
    npm run check + full ./test.sh
```

Optionally let setup run the full baseline once on first initialization.

---

# 29. Known WSL2 Generation 0 result

During the original working setup:

```text
Pi version: v0.84.2
Host: Docker Desktop on WSL2
Container user: pi
Pi source: Linux-native Docker volume
Runtime state: Linux-native Docker volume
fd: 10.4.2
```

The coding-agent test suite result was:

```text
1938 passed
49 skipped
2 failed
```

Only these two tests failed:

```text
readClipboardImage > Non-Wayland: uses clipboard
readClipboardImage > Non-Wayland: falls back to xclip when clipboard has no image
```

Inside the container:

```bash
cat /proc/version
```

showed:

```text
Linux version ... microsoft-standard-WSL2 ...
```

Pi detects WSL from `/proc/version`, causing the clipboard implementation to
take a WSL path even when the test's ordinary WSL environment variables are
stripped.

Treat this as a **known environment-specific baseline**, not as an automatic
reason to modify Pi.

Native Linux may have a different baseline.

Future Pi versions may also have a different baseline.

---

# 30. Store generation metadata

Use `/evolution` for lineage records.

Suggested layout:

```text
/evolution/
├── generations/
│   ├── generation-0000.json
│   ├── generation-0001.json
│   └── ...
├── observations/
├── evaluations/
└── CURRENT
```

Generation metadata should include at least:

```json
{
  "generation": 0,
  "timestamp": "...",
  "pi_commit": "...",
  "pi_version": "...",
  "branch": "evolve",
  "host_platform": "...",
  "kernel": "...",
  "node_version": "...",
  "npm_version": "...",
  "uv_version": "...",
  "fd_version": "...",
  "test_summary": {
    "passed": 1938,
    "failed": 2,
    "skipped": 49
  },
  "known_failures": [
    "...",
    "..."
  ]
}
```

Do not hard-code the numbers for all platforms.

The WSL2 values above are historical reference data.

---

# 31. Generation numbering

Generation 0 is the upstream baseline plus harness initialization.

A later generation should be created only when Pi's implementation or
evolution-relevant environment meaningfully changes.

Do not increment generation numbers for every ordinary project edit.

Possible criteria:

```text
new commit on /pi evolve branch
accepted harness capability change
accepted reusable agent tool/extension change
```

This can remain manual/simple in the first repository version.

Do not over-engineer generation orchestration yet.

---

# 32. `history` command

Create a command that makes lineage inspection easy.

It should show something like:

```text
Current generation
Pi commit
Git status
recent evolve commits
generation records
```

Example Git view:

```bash
git -C /pi log \
  --graph \
  --decorate \
  --oneline \
  --all \
  -30
```

Keep the output useful for humans.

---

# 33. `update` command

The first version should be conservative.

Do NOT automatically merge/rebase upstream without visibility.

Suggested behavior:

```text
git fetch origin
show current branch
show local changes
show commits available on origin/main
print suggested next command
```

Potential optional flag:

```text
--rebase
```

which performs:

```bash
git rebase origin/main
```

only when explicitly requested.

After successful integration:

```bash
npm install --ignore-scripts
npm run build
npm run check
```

Do not use global npm self-update as the canonical Pi update mechanism.

Git is canonical.

---

# 34. `shell` command

Users should be able to enter the runtime even if Pi is already running.

If container `pi-evolving` is running:

```bash
docker exec -it pi-evolving bash
```

If it is not running, create a temporary maintenance container mounting:

```text
pi-source
pi-agent-state
pi-evolution-state
```

and open Bash.

This makes commands like these easy:

```bash
git -C /pi status
npm -C /pi run check
fd --version
ls -la /evolution
```

---

# 35. Port handling

Expose a configurable local port.

Default:

```text
9191
```

Bind only to localhost by default:

```text
127.0.0.1:9191:9191
```

This avoids unintentionally exposing services to the LAN.

Allow `.env` overrides.

Pi/project processes may later use additional ports, so consider supporting an
optional list of extra port mappings, but do not complicate v1 unnecessarily.

---

# 36. Provider/model configuration

The repository must not assume all users have:

```text
llamacpp-wsl
local-coder
```

Use them only as example/default values if appropriate.

Allow `.env` configuration:

```env
PI_PROVIDER=llamacpp-wsl
PI_MODEL=local-coder
```

The launcher should pass:

```text
--provider ${PI_PROVIDER}
--model ${PI_MODEL}
```

Users must be able to change these easily.

If Pi supports interactive provider selection without these flags, document
that as an alternative.

---

# 37. Extra Pi arguments

The launcher must pass through additional arguments.

Example:

```bash
./pi.sh ~/project --foo bar
```

should ultimately append:

```text
--foo bar
```

to Pi.

PowerShell should also support argument passthrough.

---

# 38. Python project support

Generation 0 includes `uv`.

The intended experience inside a project is:

```bash
uv python install 3.14
uv venv
uv sync
```

or:

```bash
uv venv --python 3.14
uv sync
```

Do not bake Python 3.14 into the image unless later evidence justifies it.

The point is to let projects request the Python they need.

---

# 39. Environment evolution

Pi cannot normally run:

```bash
apt-get install ...
```

because it runs as non-root.

This is intentional.

If Pi decides a system dependency is broadly useful, the correct persistent
evolution path is:

```text
observe missing capability
    ↓
modify harness Dockerfile
    ↓
commit/propose change
    ↓
rebuild image
    ↓
next environment generation
```

Do not mount the Docker socket into the Pi container by default.

Pi should not automatically control the host Docker daemon in Generation 0.

---

# 40. Harness evolution

The harness repository itself may evolve.

Eventually Pi may conclude that:

```text
Dockerfile
setup scripts
test harness
volume model
launcher UX
```

should change.

This creates two related histories:

```text
harness repository
    ↓
creates environment for
    ↓
Pi lineage
    ↓
discovers substrate limitations
    ↓
proposes harness improvements
```

Do not automatically grant Pi write access to the harness repository if the
current project is unrelated.

But if the user opens the harness repository as `/workspace`, Pi may work on it
like any other project.

---

# 41. First project philosophy

Documentation should recommend that users do **not** start with:

```text
Improve yourself.
```

Instead:

```text
Understand this repository and implement feature X.

Your own source is available under /pi. If concrete limitations in your
current tools or workflow materially interfere with the task, you may inspect
and evolve yourself according to the global evolution policy.
```

We care about:

```text
Did Pi notice friction?

Was the friction real?

Did Pi pick the right layer?

Did it create a project helper?

Did it create a reusable tool?

Did it edit Pi core?

Did it improve the environment?

Did the adaptation survive testing?

Did the next generation perform better?
```

---

# 42. Testing philosophy

Self-modification must not mean:

```text
change code
-> test fails
-> change test until green
```

The policy should encourage:

```text
identify friction
-> inspect implementation
-> narrow change
-> narrow test
-> npm run check
-> broader tests if needed
-> compare with baseline
-> inspect diff
-> commit
```

Known baseline failures should be treated as controls.

A new failure is suspicious.

A baseline failure disappearing is interesting and should be understood.

---

# 43. Potential future worktree mode

Do not make this necessary for v1, but design with it in mind.

Later, Pi may evolve using Git worktrees:

```bash
git -C /pi worktree add \
  /tmp/pi-candidate \
  -b candidate/<name>
```

Then:

```text
current Pi_n
    ↓
candidate worktree
    ↓
modify
    ↓
build
    ↓
test
    ↓
evaluate
    ↓
accept / reject
```

This is a more transactional self-evolution model than directly modifying the
active checkout.

Mention this in `docs/EVOLUTION.md`.

Do not implement a complex automatic evolutionary scheduler in v1.

---

# 44. Reset operations

Provide explicit reset commands.

Users must be able to independently reset:

```text
runtime state
Pi source
evolution metadata
everything
```

Suggested interface:

```bash
./scripts/reset.sh agent-state
./scripts/reset.sh source
./scripts/reset.sh evolution
./scripts/reset.sh all
```

PowerShell equivalent:

```powershell
.\scripts\reset.ps1 agent-state
```

Require confirmation before destructive operations.

Never delete the user's `/workspace` project.

---

# 45. Backup support

Provide simple documentation and optionally scripts for backing up:

```text
pi-source
pi-agent-state
pi-evolution-state
```

At minimum, source backup is valuable.

Example:

```bash
docker run --rm \
  -v pi-evolving-source:/pi:ro \
  -v "$PWD/backups:/backup" \
  alpine \
  sh -c 'tar -czf /backup/pi-source.tar.gz -C /pi .'
```

Adjust for actual image availability or use the project image.

A remote Git branch for `/pi` is also a natural source-history backup.

Do not automatically push anything to a remote.

---

# 46. Troubleshooting documentation

Create `docs/TROUBLESHOOTING.md` covering at least:

## `fd` not found

Expected behavior:

```text
fd not found. Downloading...
fd installed to /home/pi/.pi-agent/bin/fd
```

Check:

```bash
fd --version
```

The PATH must include:

```text
/home/pi/.pi-agent/bin
```

## `dubious ownership`

The Docker image should already contain:

```bash
git config --system --add safe.directory /pi
```

If this appears, inspect volume ownership and image version.

## permission denied under `.pi-agent`

The runtime state volume must be writable by `pi`.

Check:

```bash
ls -ld /home/pi/.pi-agent
id
```

## npm/Vite chmod/EPERM issues

If `/pi` is Windows-backed, move Pi source to the Linux-native named volume.

## WSL clipboard test failures

Document the Generation 0 WSL2 known failures and `/proc/version` detection.

## stale root-owned `node_modules`

If a previous version was installed as root, reset/reinstall dependencies as
the `pi` user.

---

# 47. README requirements

The root `README.md` should be short enough that a new user can succeed without
reading all documentation.

Suggested structure:

```text
# Pi Evolving

one-paragraph explanation

## Requirements

Docker
Git

## Quick start

Windows
Linux/WSL2

## Run on a project

commands

## What persists

3 volumes + workspace

## How evolution works

short explanation

## Common commands

setup
pi
shell
test
history
update

## Documentation

links to docs/
```

Do not put the entire architecture essay in the root README.

---

# 48. `docs/ARCHITECTURE.md`

Explain:

```text
Docker image
/pi
~/.pi-agent
/evolution
/workspace
```

Include ASCII diagrams.

Explain why source and runtime state are separate.

Explain why `/pi` uses a Linux-native volume.

Explain why Pi is non-root.

Explain why Pi runs from source.

Explain why the Docker socket is not mounted.

---

# 49. `docs/EVOLUTION.md`

Explain:

```text
task-induced pressure
layer selection
self-edit workflow
generation concept
Git lineage
baseline comparison
upstream integration
future candidate worktrees
```

Include the idea that most useful evolution may happen outside Pi core:

```text
project helper
skill
extension
tool
harness
core source
Docker environment
```

That hierarchy is important.

---

# 50. `docs/GENERATION_0.md`

Record the known original setup:

```text
Pi v0.84.2
Node 24
uv available
non-root pi user
/pi on Docker volume
~/.pi-agent on Docker volume
fd 10.4.2
build PASS
check PASS
WSL2 coding-agent tests:
    1938 pass
    49 skip
    2 known clipboard fails
```

Clarify that this is historical reference, not a permanent universal expected
count.

Provide a command for users to record their own baseline.

---

# 51. `docs/SETUP.md`

This can contain the long/manual version for advanced users.

Include:

```text
raw docker commands
volume creation
manual Pi clone
manual npm install
manual build
manual check
manual test
manual run
manual shell
manual reset
```

This document is where the technical details live.

The normal user should not need it.

---

# 52. WSL2 guidance

For Windows users:

```text
PowerShell + Docker Desktop
```

should work with `/pi` and agent state in named volumes.

The user project may be a Windows bind mount.

For Linux-heavy projects, recommend cloning the workspace under WSL2:

```text
/home/<user>/src/project
```

and running from a WSL shell.

Explain that Linux-heavy operations generally behave more naturally there.

Do not force all Windows users into WSL just to start.

---

# 53. Native Linux UID/GID

On Linux, matching host UID/GID is convenient.

Support:

```bash
docker build \
  --build-arg PI_UID="$(id -u)" \
  --build-arg PI_GID="$(id -g)" \
  ...
```

The setup script may detect native Linux and do this automatically.

Be careful not to break the named volume ownership model.

If automatic UID/GID handling becomes complicated, default to `1001:1001` in
v1 and document the advanced override.

Prefer correctness over cleverness.

---

# 54. Script quality

All scripts should:

- be readable;
- be idempotent where appropriate;
- print clear phase messages;
- fail on real errors;
- not silently destroy state;
- quote paths correctly;
- work from any current directory if feasible;
- resolve the repository root relative to the script;
- avoid relying on user's current working directory except for explicit
  workspace arguments.

Avoid huge monolithic scripts.

Factor shared operations into:

```text
scripts/common.sh
scripts/common.ps1
```

where it actually reduces duplication.

---

# 55. State detection

Useful helper checks:

```text
Does image exist?
Does volume exist?
Does /pi/.git exist?
Does evolve branch exist?
Does /pi/node_modules exist?
Does ~/.pi-agent/AGENTS.md exist?
Does fd exist?
Does /evolution/generations/generation-0000.json exist?
```

Use these to make setup resumable after interruption.

A failed setup should be safe to rerun.

---

# 56. Do not assume empty volumes remain empty

When initializing, always check actual contents.

For example:

```bash
test -d /pi/.git
```

is better than assuming "volume exists means initialized."

Similarly:

```text
volume absent
volume present but empty
volume present and partially initialized
volume fully initialized
```

should be treated distinctly where useful.

---

# 57. Volume ownership helper

Because the image normally runs as `pi`, setup may need one short root container
to initialize ownership:

```bash
docker run --rm \
  --entrypoint bash \
  --user root \
  -v pi-source:/pi \
  -v pi-agent-state:/home/pi/.pi-agent \
  -v pi-evolution-state:/evolution \
  pi-evolving \
  -lc 'chown -R pi:pi /pi /home/pi/.pi-agent /evolution'
```

After bootstrap, ordinary work should use `pi`.

---

# 58. First-start `fd`

One complication:

Pi may only download `fd` after it starts interactively.

The setup script can either:

### Option A

Run Pi once and let it acquire `fd`.

### Option B

Trigger the same Pi tool manager path indirectly.

### Option C

Leave setup complete without `fd` and tell the user:

```text
First Pi launch may download fd automatically.
```

For v1, Option C is perfectly acceptable.

The important thing is that `PATH` already includes the persistent bin
directory.

---

# 59. Testing `fd`

Before the full Pi test suite, test:

```bash
command -v fd
fd --version
```

If absent, the test script may print:

```text
fd has not yet been acquired. Start Pi once, then rerun tests.
```

Alternatively, the test script may launch Pi/help in a way that causes tool
acquisition if that is reliable.

Do not add Debian `fd-find` as a shortcut.

---

# 60. Protect secrets

Never:

```text
commit ~/.pi-agent
copy auth.json into repository
print secrets into generation metadata
backup credentials into Git
```

Generation metadata should record only non-secret environment facts.

If users configure API keys via environment variables, do not persist them
unless Pi itself intentionally manages auth through its normal mechanisms.

---

# 61. `.gitignore`

At minimum ignore:

```text
.env
backups/
*.log
.DS_Store
Thumbs.db
```

Do not ignore source files needed by the harness.

The named volume contents are not present in the harness working tree anyway.

---

# 62. Optional wrapper command

After v1 works, consider a single executable-like interface:

```text
pi-evolving setup
pi-evolving run <workspace>
pi-evolving shell
pi-evolving test
pi-evolving history
pi-evolving update
```

But do not delay the repository by building a full CLI framework.

Shell + PowerShell scripts are enough for the first version.

---

# 63. Acceptance criteria

The repository is not finished until all of these are true.

## Fresh setup

On a clean machine with Docker available:

```text
clone harness
run setup
```

must:

```text
build image
create volumes
clone Pi
create evolve branch
install dependencies
build Pi
run checks
install evolution policy
finish without manual Docker commands
```

## Persistence

Start Pi, stop/remove the container, start Pi again.

These must persist:

```text
/pi Git repository
/pi evolve commits
node_modules/build state
~/.pi-agent settings
downloaded fd
sessions
/evolution metadata
```

## Workspace independence

Run:

```text
pi <project A>
stop
pi <project B>
```

Both projects should use the same evolving Pi lineage.

## Source mutation

Inside Pi/container:

```bash
touch /pi/.test
rm /pi/.test
```

must succeed.

## Permission semantics

As `pi`:

```bash
tmp=$(mktemp)
echo hello > "$tmp"
chmod 400 "$tmp"
echo world > "$tmp"
```

must fail with permission denied.

## Git

```bash
git -C /pi status
```

must work without dubious ownership warnings.

## fd

After Pi acquires it:

```bash
fd --version
```

must work from a maintenance shell.

## Build

```bash
cd /pi
npm run build
npm run check
```

must succeed.

## Test harness

The test command must run the full Pi test suite and display a concise summary.

Under WSL2, known clipboard failures may remain and should be identified as
baseline differences rather than generic failure noise.

## User experience

Normal use must not require users to type long `docker run` commands.

---

# 64. Manual test scenario

After implementation, perform this complete scenario.

### Step 1

Fresh clone harness.

### Step 2

Run:

```text
setup
```

### Step 3

Inspect:

```text
docker volume ls
```

Verify all three persistent volumes exist.

### Step 4

Run Pi against a small test project.

### Step 5

Allow Pi to acquire `fd`.

### Step 6

Open a maintenance shell.

Verify:

```bash
whoami
id
fd --version
git -C /pi status
```

### Step 7

Run full test command.

### Step 8

Create a harmless commit in `/pi` on `evolve`.

For example, modify a documentation-only file or create an experiment note if
appropriate.

### Step 9

Stop/remove the container.

### Step 10

Start Pi again.

Verify the commit still exists.

### Step 11

Run Pi against a different workspace.

Verify the same Pi lineage is used.

### Step 12

Run `history`.

Verify the lineage is visible.

---

# 65. Do not fake evolution

Do not implement a "self evolution" button that blindly modifies code.

The repository's job is to create the conditions:

```text
persistent source
Git lineage
tests
runtime state
real workspace
policy
generation metadata
```

The agent itself decides whether concrete task friction justifies adaptation.

---

# 66. Keep v1 intentionally simple

Do NOT add yet unless clearly necessary:

```text
Kubernetes
database service
message queue
web control plane
background scheduler
multi-agent orchestration
automatic genetic algorithms
automatic branch scoring
host Docker socket
privileged containers
remote telemetry backend
complex web UI
```

A small repository that actually works is more valuable than a grand platform.

---

# 67. Implementation phases

Build this repository in phases.

## Phase 1 — substrate

Create:

```text
docker/Dockerfile
compose.yaml
.env.example
```

Verify image build.

## Phase 2 — persistent initialization

Create setup scripts that:

```text
create volumes
initialize ownership
clone Pi
create evolve
configure Git
install dependencies
build/check
```

Verify idempotency.

## Phase 3 — normal launcher

Create:

```text
pi.sh
pi.ps1
```

Verify arbitrary workspace mounts.

## Phase 4 — evolution policy

Create:

```text
config/AGENTS.md
```

Install it into runtime state during setup.

## Phase 5 — maintenance commands

Create:

```text
shell
test
history
update
reset
```

## Phase 6 — generation metadata

Create simple `/evolution` metadata recording.

Do not over-engineer.

## Phase 7 — documentation

Write:

```text
README
ARCHITECTURE
SETUP
EVOLUTION
TROUBLESHOOTING
GENERATION_0
```

## Phase 8 — end-to-end validation

Run the complete manual test scenario.

Fix real portability/quoting/idempotency problems.

---

# 68. How to report your work

As you implement:

1. keep changes in small coherent steps;
2. test each phase;
3. update README/docs as behavior changes;
4. avoid claiming cross-platform support that was not actually implemented;
5. note anything that could not be tested locally.

At the end provide:

```text
repository tree
quick-start commands
what was tested
known limitations
next useful extensions
```

---

# 69. Design priorities

When making implementation choices, prioritize in this order:

```text
1. reliable persistence
2. understandable state model
3. simple user experience
4. Linux-native semantics for Pi itself
5. cross-platform launcher ergonomics
6. inspectable Git lineage
7. safe/idempotent bootstrap
8. evolvability
9. convenience
10. sophistication
```

---

# 70. Core mental model

The repository should make this true:

```text
clone harness
    ↓
setup
    ↓
Generation 0 Pi exists
    ↓
run Pi on real project
    ↓
Pi observes real friction
    ↓
Pi may inspect /pi
    ↓
Pi may adapt at the smallest useful layer
    ↓
test/evaluate
    ↓
commit evolve change
    ↓
restart
    ↓
next generation
```

The project is successful if another user can reach that state with only a
small number of commands and without understanding all the Docker details that
made it possible.

---

# 71. Final instruction

Implement the repository now.

Do not merely write a design document.

Create the actual files, scripts, Dockerfile, Compose configuration, evolution
policy, and documentation.

Start with the smallest working version, test it, then improve it.

When a design decision is ambiguous, prefer the solution that keeps the
architecture visible and easy to modify later.
