# Pi Evolving

Pi Evolving runs the [earendil-works/pi](https://github.com/earendil-works/pi)
coding agent from a persistent source checkout inside Docker. Pi works on any
mounted project while its own source, runtime state, and evolution records
survive container removal. Real project friction—not a blind “improve
yourself” loop—drives focused, tested changes on an `evolve` branch.

## Choose your setup

### Local NVIDIA GPU: Qwen3.8-27B

Start with the
[complete first-time local model guide](docs/QWEN38_27B.md). It covers building
llama.cpp with CUDA, downloading the quantized model, GPU and host-memory
sizing, WSL2 and native Linux, and troubleshooting.

The recommended profile uses the 17.6 GB Unsloth `UD-Q4_K_XL` GGUF and is
intended for an RTX 3090, 4090, 5090, or another NVIDIA GPU with sufficient
memory. It serves the model on port `18080`.

After building llama.cpp, use terminal 1 in WSL2 or Linux to download and run
the model:

```bash
./scripts/models/qwen3.8-27b/download.sh
./scripts/models/qwen3.8-27b/serve.sh
```

Keep that terminal open. In terminal 2, initialize Pi with the running model:

```bash
./setup.sh --model qwen3.8-27b
./pi.sh /path/to/project
```

Or initialize Pi from Windows PowerShell while llama-server runs in WSL2:

```powershell
.\setup.ps1 -Model qwen3.8-27b
.\pi.ps1 C:\path\to\project
```

The download is explicit because it transfers approximately 17.6 GB. Setup
verifies the model before building Pi and runs another completion check through
Docker before selecting it.

### Existing or remote provider

Use the standard setup below. It leaves the provider and model unset so Pi can
use its normal selection flow or a provider you configure later.

## Requirements

- Docker with Docker Compose v2
- Git (to clone this harness)

The image supplies Node 24, npm, Git, uv/uvx, compilers, and common Unix tools.

## Standard quick start

Windows PowerShell:

```powershell
git clone <pi-evolving-repository-url>
cd pi-evolving
.\setup.ps1
.\pi.ps1 C:\work\my-project
```

Linux or WSL2:

```bash
git clone <pi-evolving-repository-url>
cd pi-evolving
./setup.sh
./pi.sh ~/work/my-project
```

Setup creates `.env` from `.env.example`. Provider and model are blank by
default so Pi can use its normal selection flow. To configure them explicitly,
first inspect the choices with `./pi.sh PATH --list-models` (or the PowerShell
equivalent), then edit `PI_PROVIDER` and `PI_MODEL`. Extra arguments pass through:

```bash
./pi.sh ~/work/my-project --some-pi-flag value
```

## What persists

| Location | Storage | Purpose |
|---|---|---|
| `/pi` | `pi-evolving-source` volume | Pi source, Git lineage, dependencies, builds |
| `/agent` | optional host bind mount | version-controlled reusable extensions, skills, and prompts |
| `/home/pi/.pi-agent` | `pi-evolving-agent-state` volume | settings, sessions, auth metadata, acquired tools |
| `/evolution` | `pi-evolving-evolution-state` volume | generations, observations, evaluations |
| `/workspace` | host bind mount | the project supplied to `pi.sh`/`pi.ps1` |

Project-level `/workspace/AGENTS.md` instructions remain in effect alongside
the global evolution policy installed in Pi's runtime state.

## Common commands

| Task | Linux/WSL2 | PowerShell |
|---|---|---|
| Bootstrap/update build | `./setup.sh` | `.\setup.ps1` |
| Run on a project | `./pi.sh PATH` | `.\pi.ps1 PATH` |
| Maintenance shell | `./shell.sh` | `.\shell.ps1` |
| Full Pi tests | `./test.sh` | `.\test.ps1` |
| Agent capabilities | `./scripts/agent.sh status` | `.\scripts\agent.ps1 status` |
| Inspect lineage | `./scripts/history.sh` | `.\scripts\history.ps1` |
| Inspect upstream | `./scripts/update.sh` | `.\scripts\update.ps1` |
| Explicit rebase | `./scripts/update.sh --rebase` | `.\scripts\update.ps1 -Rebase` |
| Enable generic llama.cpp | `./scripts/local-model.sh` | `.\scripts\local-model.ps1` |
| Check Qwen3.8 server | `./scripts/models/qwen3.8-27b/check.sh` | Run the Bash command in WSL2 |

Reset operations are explicit and confirmed; see [setup and operations](docs/SETUP.md).

### Version-controlled agent capabilities

Reusable extensions, skills, and prompts can live in a separate Git repository
mounted at `/agent`; `.pi-agent` remains installed runtime state. Set its
absolute host path in `.env`:

```dotenv
PI_AGENT_EVOLUTION_PATH=/home/me/gits/pi-agent-evolution
PI_AGENT_AUTO_INSTALL=1
```

Copy [`config/agent.example.json`](config/agent.example.json) to that
repository as `agent.json` and declare the files to install. Setup and every Pi
launch install its current committed state safely. They never fetch or pull,
reject a dirty repository, and refuse to overwrite runtime drift. See the
[agent evolution guide](docs/AGENT_EVOLUTION.md) for initial migration and
candidate testing.

### Generic local llama.cpp preset

The repository includes `config/models.llamacpp-wsl.json` for a llama.cpp
server running on the host on port `18080`. This is the model-neutral preset;
the Qwen first-run profile above uses the same port with model-specific
settings. Start the server with a network-visible listener, then enable the
preset. See the full
[llama.cpp build and setup guide](docs/LLAMA_CPP.md) for CUDA prerequisites,
model selection, memory sizing, networking, and troubleshooting.

```bash
llama-server --model /path/to/model.gguf --host 0.0.0.0 --port 18080
./scripts/local-model.sh
```

```powershell
.\scripts\local-model.ps1
```

The command checks connectivity, backs up an existing persistent `models.json`,
installs the preset, and selects `llamacpp-wsl/local-coder` in `.env`. Use
`--skip-check` or `-SkipCheck` to install while the model server is offline.

## How evolution works

Pi first solves the workspace task. If repeated, concrete friction exposes a
missing capability, it selects the smallest useful layer, tests an adaptation,
and retains or reverts it. Pi core changes live as focused `evolve:` commits in
`/pi`; a restart activates the next generation. Nothing automatically pushes
to a remote or mounts the host Docker socket.

## Documentation

- [Architecture](docs/ARCHITECTURE.md)
- [Setup and operations](docs/SETUP.md)
- [Evolution model](docs/EVOLUTION.md)
- [Agent capability evolution](docs/AGENT_EVOLUTION.md)
- [Generation 0 reference](docs/GENERATION_0.md)
- [Build and run llama.cpp on Linux or WSL2](docs/LLAMA_CPP.md)
- [Deploy Qwen3.8-27B on a 24 GB or larger NVIDIA GPU](docs/QWEN38_27B.md)
- [Troubleshooting](docs/TROUBLESHOOTING.md)
