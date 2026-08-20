# Pi Evolving

Pi Evolving runs the [earendil-works/pi](https://github.com/earendil-works/pi)
coding agent from a persistent source checkout inside Docker. Pi works on any
mounted project while its own source, runtime state, and evolution records
survive container removal. Real project friction—not a blind “improve
yourself” loop—drives focused, tested changes on an `evolve` branch.

## Requirements

- Docker with Docker Compose v2
- Git (to clone this harness)

The image supplies Node 24, npm, Git, uv/uvx, compilers, and common Unix tools.

## Quick start

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

### First run with quantized Qwen3.8-27B

For the repository's recommended single-GPU profile, first download and start
the Unsloth `UD-Q4_K_XL` GGUF from WSL2 or Linux:

```bash
./scripts/models/qwen3.8-27b/download.sh
./scripts/models/qwen3.8-27b/serve.sh
```

Keep the server running, then initialize Pi in another shell. Selecting the
profile makes setup verify the server before building, install the matching Pi
configuration, and run a completion smoke test:

```bash
./setup.sh --model qwen3.8-27b
./pi.sh ~/work/my-project
```

```powershell
.\setup.ps1 -Model qwen3.8-27b
.\pi.ps1 C:\work\my-project
```

The download is explicit because it transfers roughly 17--19 GB. See the
[Qwen3.8-27B deployment guide](docs/QWEN38_27B.md) before the first download.

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
| Inspect lineage | `./scripts/history.sh` | `.\scripts\history.ps1` |
| Inspect upstream | `./scripts/update.sh` | `.\scripts\update.ps1` |
| Explicit rebase | `./scripts/update.sh --rebase` | `.\scripts\update.ps1 -Rebase` |
| Enable WSL2 llama.cpp | `./scripts/local-model.sh` | `.\scripts\local-model.ps1` |
| Check Qwen3.8 server | `./scripts/models/qwen3.8-27b/check.sh` | Run the Bash command in WSL2 |

Reset operations are explicit and confirmed; see [setup and operations](docs/SETUP.md).

### Local llama.cpp preset

The repository includes `config/models.llamacpp-wsl.json` for a llama.cpp
server running under WSL2 on port 8080. Start the server with a network-visible
listener, then enable the preset. See the full
[llama.cpp build and setup guide](docs/LLAMA_CPP.md) for CUDA prerequisites,
model selection, memory sizing, networking, and troubleshooting.

```bash
llama-server --model /path/to/model.gguf --host 0.0.0.0 --port 8080
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
- [Generation 0 reference](docs/GENERATION_0.md)
- [Build and run llama.cpp under WSL2](docs/LLAMA_CPP.md)
- [Deploy Qwen3.8-27B on a 24 GB or larger NVIDIA GPU](docs/QWEN38_27B.md)
- [Troubleshooting](docs/TROUBLESHOOTING.md)
