# Deploying Qwen3.8-27B with llama.cpp

As of 2026-08-20, Qwen3.8-27B is the recommended high-intelligence-density
model in this repository for a single 24 GB or larger NVIDIA GPU. It is a
27-billion-parameter dense, hybrid-thinking model aimed at agentic coding and
chat. This is a dated recommendation, not a permanent claim that no newer
model is better.

This profile uses Unsloth's `UD-Q4_K_XL` GGUF. Unsloth estimates 17--19 GB of
combined RAM and VRAM for the 4-bit model, leaving usable but workload-dependent
headroom on an RTX 3090 or 4090 and more headroom on an RTX 5090. The model
supports up to 256K context, but this guide starts at 73,728 tokens because KV
cache and runtime workspace need memory in addition to the model weights. The
practical context limit depends on both GPU VRAM and available host RAM, as well
as llama.cpp's offload choices.

References:

- [Qwen3.8-27B model and memory guidance](https://unsloth.ai/models/qwen3.8-27b)
- [Unsloth Qwen3.8-27B GGUF repository](https://huggingface.co/unsloth/Qwen3.8-27B-GGUF)
- [llama-server options and environment variables](https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md)
- [Building llama.cpp with CUDA](LLAMA_CPP.md)

## Directory layout

Use the XDG directories for small configuration and state, and keep large model
weights under a separately overridable root:

```text
~/.config/pi-evolving/models/       per-model environment profiles
~/.local/share/llama.cpp/models/    default model root on Linux
  unsloth/
    Qwen3.8-27B-GGUF/
      Qwen3.8-27B-UD-Q4_K_XL.gguf
~/.local/state/pi-evolving/         optional logs and service state
```

On native Linux, the default under `~/.local/share` gives predictable mmap and
filesystem performance. Under WSL2, a Windows-mounted data disk is reasonable
when capacity and Windows access matter, although loading can be slower than
from the WSL2 filesystem. Override only the large-data root:

```bash
export LOCAL_MODELS_ROOT=/mnt/e/models
```

That produces the path used in the example above:
`/mnt/e/models/unsloth/Qwen3.8-27B-GGUF`.

## 1. Load the model profile

The repository includes
[`models/qwen3.8-27b/model.env.example`](../models/qwen3.8-27b/model.env.example).
The model scripts copy it to the user configuration directory automatically so
local changes do not dirty the Git working tree. To create the profile before
downloading, run:

```bash
./scripts/models/qwen3.8-27b/download.sh
```

The command stops with an installation command if the Hugging Face CLI is
missing. On WSL2 with models stored on drive E, set the override before the
first download. On native Linux, omit the first line to use the XDG default:

```bash
export LOCAL_MODELS_ROOT=/mnt/e/models
./scripts/models/qwen3.8-27b/download.sh
```

Subsequent runs reuse the user profile at
`~/.config/pi-evolving/models/qwen3.8-27b.env`. Edit that file for persistent
local changes.

Profiles created before the Qwen-specific port changed from 8080 to 18080 are
not overwritten. Migrate an existing profile once:

```bash
sed -i 's/LLAMA_ARG_PORT="8080"/LLAMA_ARG_PORT="18080"/' \
  "${XDG_CONFIG_HOME:-$HOME/.config}/pi-evolving/models/qwen3.8-27b.env"
```

Inspect the resolved paths before downloading roughly 17--19 GB:

```bash
source "${XDG_CONFIG_HOME:-$HOME/.config}/pi-evolving/models/qwen3.8-27b.env"
printf 'Repository: %s\nQuant:      %s\nFile:       %s\n' \
  "$HF_MODEL_REPO" "$MODEL_QUANT" "$MODEL_FILE"
```

The profile uses llama.cpp's native `LLAMA_ARG_*` variables wherever the
server supports them. The four `LOCAL_MODEL_*` sampler variables are expanded
by the launch command because llama-server does not currently publish native
environment variables for every sampler default.

## 2. Download the GGUF

Install the Hugging Face CLI in the active Python environment:

```bash
python -m pip install -U "huggingface_hub[cli]"
```

The dedicated download command creates the repository-shaped model directory
and downloads only the selected quantization:

```bash
./scripts/models/qwen3.8-27b/download.sh
```

Keeping the Hugging Face organization and repository in the local path avoids
filename collisions and makes provenance obvious. Re-running `hf download` is
safe and resumes or reuses already downloaded content.

This first-run profile intentionally requires `UD-Q4_K_XL`; it will reject a
different value to prevent an accidental mismatch between the documented and
deployed model. Unsloth also publishes smaller quantizations, but those should
be added as separate, explicitly tested profiles rather than silently replacing
this one.

## 3. Start llama-server

Build and expose `llama-server` on `PATH` first by following
[the llama.cpp CUDA guide](LLAMA_CPP.md). Confirm the device name used by the
profile:

```bash
llama-server --list-devices
```

The expected single-GPU name is `CUDA0`. If yours differs, edit
`LLAMA_ARG_DEVICE` in the copied profile and source it again.

Start the server with the model and server settings supplied through the
environment:

```bash
./scripts/models/qwen3.8-27b/serve.sh
```

The script runs llama-server in the foreground. Keep that shell open while Pi
is using the model. The complete environment and sampling configuration remains
visible in the tracked profile and can be audited without running the script.

The chosen defaults are:

| Setting | Value | Reason |
|---|---:|---|
| Quantization | `UD-Q4_K_XL` | Recommended quality/memory balance |
| GPU layers | `all` | Keep all model layers on the GPU |
| Server context | `73728` | 65,536-token Pi window plus server headroom |
| Server port | `18080` | Avoid common Jupyter and development-server collisions |
| Parallel slots | `1` | Dedicate the KV cache to one coding-agent session |
| K/V cache | `q4_0` | Reduce long-context VRAM use |
| Flash attention | `on` | Improve supported CUDA attention performance |
| MTP draft tokens | `2` | Use the model's built-in draft-MTP capability |
| Sampling | `1.0 / 0.95 / 20 / 0` | Unsloth's thinking-mode defaults |

Command-line arguments override `LLAMA_ARG_*` variables, so temporary tests do
not require editing the profile. For example:

```bash
source "${XDG_CONFIG_HOME:-$HOME/.config}/pi-evolving/models/qwen3.8-27b.env"
llama-server --ctx-size 32768 \
  --temp "$LOCAL_MODEL_TEMPERATURE" \
  --top-p "$LOCAL_MODEL_TOP_P" \
  --top-k "$LOCAL_MODEL_TOP_K" \
  --min-p "$LOCAL_MODEL_MIN_P"
```

`local-dev-key` is a compatibility placeholder used by Pi Evolving, not a
secret. Binding to `0.0.0.0` is needed for container access, so do not expose
port 18080 through a router or to an untrusted network. Use a private value in
both llama-server and Pi's model configuration if the host is reachable by
other users.

## 4. Verify and connect Pi

In a second shell, verify the model alias and optionally run a direct completion:

```bash
./scripts/models/qwen3.8-27b/check.sh
./scripts/models/qwen3.8-27b/check.sh --smoke-test
```

For a first-time setup, select the profile explicitly. Setup performs an early
host-side check before the build, installs the Qwen-specific `models.json`, and
performs another completion smoke test through the same Docker route Pi uses:

```bash
./setup.sh --model qwen3.8-27b
./pi.sh /path/to/workspace
```

From PowerShell when Pi Evolving runs through Docker Desktop:

```powershell
.\setup.ps1 -Model qwen3.8-27b
.\pi.ps1 C:\path\to\workspace
```

If Pi is already initialized, enable the profile without rebuilding:

```bash
./scripts/local-model.sh --profile qwen3.8-27b --smoke-test
```

```powershell
.\scripts\local-model.ps1 -Profile qwen3.8-27b -SmokeTest
```

The preset advertises a 65,536-token window to Pi while llama-server allocates
73,728 tokens. The difference is intentional server-side safety margin. The
repository's Docker launchers map `host.docker.internal` to the host gateway,
so the same preset works with Docker Desktop and native Linux Docker.

## Memory tuning

The profile above is the known-good baseline for this model. Keep its sampling,
MTP, cache, and flash-attention settings unless memory pressure requires a
specific compromise.

### How context consumes memory

Context is not determined by GPU capacity alone:

- Model weights consume most of the initial allocation. With
  `LLAMA_ARG_N_GPU_LAYERS=all`, llama.cpp attempts to keep all layers in VRAM,
  while the GGUF file may also be memory-mapped and backed by the host page
  cache.
- The KV cache grows with context length and the number of parallel slots. Its
  default location is the GPU; this profile uses one slot and `q4_0` K/V values
  to make 73,728 tokens practical on 24 GB cards.
- CUDA work buffers, flash attention, and MTP require additional working VRAM.
- Host RAM holds operating-system overhead, mapped model pages, CPU-resident
  layers, and any fallback allocations. More host RAM can make partial offload
  viable, but transfers between system memory and the GPU reduce performance.

Under WSL2, `free -h` reports the memory available to the WSL virtual machine,
which may be lower than the physical RAM installed in Windows. Check both host
RAM and VRAM before selecting a context:

```bash
free -h
watch -n 1 nvidia-smi
```

Test with a realistically long prompt; successful model loading alone does not
prove that the full context fits. If CUDA or the host reports out of memory,
make one change at a time in this order:

1. Reduce `LLAMA_ARG_CTX_SIZE` to `65536`, `32768`, or `16384`.
2. Disable MTP with `unset LLAMA_ARG_SPEC_TYPE LLAMA_ARG_SPEC_DRAFT_N_MAX`.
3. Keep the `q4_0` K/V cache and verify `LLAMA_ARG_N_PARALLEL=1`.
4. Use the `UD-Q3_K_XL` GGUF.
5. Remove full offload or let llama.cpp fit some work outside VRAM, accepting
   slower inference.

After reducing the server below 65,536 tokens, also lower `contextWindow` in
`models/qwen3.8-27b/models.json` and reinstall the Pi profile. Never advertise
more context to Pi than llama-server can accept.

The RTX 5090 can also use Blackwell-specific NVFP4 deployments. Unsloth reports
substantially higher speed for that format, but it requires a different serving
stack. This guide deliberately uses GGUF and llama.cpp because the same profile
works across RTX 3090, 4090, and 5090 systems.
