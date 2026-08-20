# Setup and operations

The root scripts are the supported interface. This document exposes their
Docker operations for inspection and recovery.

## Configuration

On first setup, `.env.example` is copied to `.env`. Provider/model are blank by
default; run Pi with `--list-models` before setting them explicitly. The file
also controls ports, image name, and the Git identity used only inside `/pi`.
Do not put API keys in the harness. Pi's normal authentication state belongs in
its persistent agent-state volume.

Linux-heavy Windows projects generally behave best under WSL2, for example
`/home/<user>/src/project`, but PowerShell and Windows workspace bind mounts are
supported. Pi source always stays in a Linux-native named volume.

Advanced native-Linux builds can set `PI_UID` and `PI_GID` before Compose build;
v1 defaults to the predictable `1001:1001` volume ownership model.

## What setup does

Setup checks Docker, builds `pi-evolving:local`, creates three named volumes,
fixes ownership, clones upstream if `/pi/.git` is absent, creates `evolve`, and
sets a local Git identity if missing. It then runs:

```bash
cd /pi
npm install --ignore-scripts
npm run build
npm run check
```

Finally it installs `config/AGENTS.md` and creates the Generation 0 record. An
existing checkout, Git changes, sessions, tools, and evolution records are not
reset. If a global policy differs, setup timestamps a backup before updating
the managed policy.

## Equivalent manual Docker operations

Build and create volumes:

```bash
docker compose build pi
docker volume create pi-evolving-source
docker volume create pi-evolving-agent-state
docker volume create pi-evolving-evolution-state
```

All maintenance containers use these mounts:

```bash
docker run --rm --entrypoint bash \
  -v pi-evolving-source:/pi \
  -v pi-evolving-agent-state:/home/pi/.pi-agent \
  -v pi-evolving-evolution-state:/evolution \
  pi-evolving:local
```

Inside that shell, a fully manual first source initialization is:

```bash
git clone https://github.com/earendil-works/pi.git /pi
git -C /pi switch -c evolve
cd /pi
npm install --ignore-scripts
npm run build
npm run check
./test.sh
```

The launcher additionally bind-mounts an absolute host project at `/workspace`,
publishes `127.0.0.1:9191:9191`, and runs `/pi/pi-test.sh` through `tini`.

## Maintenance and updates

`shell` enters the named running container when available, otherwise it opens a
temporary container with all persistent volumes. `test` checks for fd, runs
`npm run check` and the full upstream suite, then records its output.

`scripts/update` fetches and reports `origin/main`. Rebase only after review:

```bash
./scripts/update.sh --rebase
```

```powershell
.\scripts\update.ps1 -Rebase
```

## Local llama.cpp under WSL2

The tracked `config/models.llamacpp-wsl.json` preset points to
`http://host.docker.internal:8080/v1`. Run llama.cpp in WSL2 with a listener
reachable through Docker Desktop:

For CUDA installation, building, model selection, memory sizing, and detailed
troubleshooting, read [Building llama.cpp for local models](LLAMA_CPP.md).

```bash
llama-server --model /path/to/model.gguf --host 0.0.0.0 --port 8080
```

Install and select the preset without manually writing JSON:

```bash
./scripts/local-model.sh
```

```powershell
.\scripts\local-model.ps1
```

### First setup with Qwen3.8-27B

The explicit Qwen profile uses Unsloth's quantized `UD-Q4_K_XL` GGUF. Download
and start it from WSL2 or Linux first. Its dedicated default port is `18080`,
avoiding the commonly occupied port 8080 used by the generic preset:

```bash
./scripts/models/qwen3.8-27b/download.sh
./scripts/models/qwen3.8-27b/serve.sh
```

In another shell, select it during setup:

```bash
./setup.sh --model qwen3.8-27b
```

```powershell
.\setup.ps1 -Model qwen3.8-27b
```

An explicit model selection is strict: setup stops before the build if the
endpoint or `local-coder` alias is unavailable. After initialization it checks
the endpoint again from Docker, runs a short completion, installs
`models/qwen3.8-27b/models.json`, and selects the provider in `.env`. Plain
setup remains model-neutral.

The installer validates the endpoint, saves a timestamped backup when replacing
`/home/pi/.pi-agent/models.json`, writes the preset with mode `0600`, and updates
`PI_PROVIDER` and `PI_MODEL` in `.env`. It never alters the workspace. To stage
the configuration while llama.cpp is stopped, use `--skip-check` in Bash or
`-SkipCheck` in PowerShell.

## Backups

Source Git history is best backed up to a user-controlled remote; this harness
never pushes automatically. A local archive can be created with the project
image (create `backups` first):

```bash
mkdir -p backups
docker run --rm --entrypoint bash \
  -v pi-evolving-source:/data:ro \
  -v "$PWD/backups:/backup" \
  pi-evolving:local -lc 'tar -czf /backup/pi-source.tar.gz -C /data .'
```

Repeat with the other volume names only if you intentionally want to back up
runtime state; it may contain credentials and must be protected.

## Reset

Resets never mount or delete the workspace. Each requires typing the target:

```bash
./scripts/reset.sh agent-state
./scripts/reset.sh source
./scripts/reset.sh evolution
./scripts/reset.sh all
```

PowerShell uses the same target names with `reset.ps1`. Deleted named-volume
data is not recoverable without a backup. Run setup afterward to recreate it.
