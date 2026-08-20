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
[`config/qwen3.8-27b.env.example`](../config/qwen3.8-27b.env.example). Copy it
to the user configuration directory so local changes do not dirty the Git
working tree:

```bash
MODEL_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}/pi-evolving/models"
mkdir -p "$MODEL_CONFIG_HOME"
cp config/qwen3.8-27b.env.example "$MODEL_CONFIG_HOME/qwen3.8-27b.env"
```

On WSL2 with models stored on drive E, set the override before sourcing the
profile. On native Linux, omit the first line to use the XDG default:

```bash
export LOCAL_MODELS_ROOT=/mnt/e/models
source "${XDG_CONFIG_HOME:-$HOME/.config}/pi-evolving/models/qwen3.8-27b.env"
```

Inspect the resolved paths before downloading roughly 17--19 GB:

```bash
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

Create the repository-shaped model directory and download only the selected
quantization:

```bash
mkdir -p "$MODEL_DIR"

hf download "$HF_MODEL_REPO" \
  --local-dir "$MODEL_DIR" \
  --include "*$MODEL_QUANT*"

test -f "$MODEL_FILE"
```

Keeping the Hugging Face organization and repository in the local path avoids
filename collisions and makes provenance obvious. Re-running `hf download` is
safe and resumes or reuses already downloaded content.

For tighter cards, change both `MODEL_QUANT` and `MODEL_FILE` in the copied
profile to `UD-Q3_K_XL` before downloading. Unsloth estimates 13--16 GB total
memory for the 3-bit option, at some quality cost.

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
llama-server \
  --temp "$LOCAL_MODEL_TEMPERATURE" \
  --top-p "$LOCAL_MODEL_TOP_P" \
  --top-k "$LOCAL_MODEL_TOP_K" \
  --min-p "$LOCAL_MODEL_MIN_P"
```

The chosen defaults are:

| Setting | Value | Reason |
|---|---:|---|
| Quantization | `UD-Q4_K_XL` | Recommended quality/memory balance |
| GPU layers | `all` | Keep all model layers on the GPU |
| Server context | `73728` | 65,536-token Pi window plus server headroom |
| Parallel slots | `1` | Dedicate the KV cache to one coding-agent session |
| K/V cache | `q4_0` | Reduce long-context VRAM use |
| Flash attention | `on` | Improve supported CUDA attention performance |
| MTP draft tokens | `2` | Use the model's built-in draft-MTP capability |
| Sampling | `1.0 / 0.95 / 20 / 0` | Unsloth's thinking-mode defaults |

Command-line arguments override `LLAMA_ARG_*` variables, so temporary tests do
not require editing the profile. For example:

```bash
llama-server --ctx-size 32768 \
  --temp "$LOCAL_MODEL_TEMPERATURE" \
  --top-p "$LOCAL_MODEL_TOP_P" \
  --top-k "$LOCAL_MODEL_TOP_K" \
  --min-p "$LOCAL_MODEL_MIN_P"
```

`local-dev-key` is a compatibility placeholder used by Pi Evolving, not a
secret. Binding to `0.0.0.0` is needed for container access, so do not expose
port 8080 through a router or to an untrusted network. Use a private value in
both llama-server and Pi's model configuration if the host is reachable by
other users.

## 4. Verify and connect Pi

In a second shell, load the same profile and query the server:

```bash
source "${XDG_CONFIG_HOME:-$HOME/.config}/pi-evolving/models/qwen3.8-27b.env"

curl --fail \
  -H "Authorization: Bearer $LLAMA_API_KEY" \
  "http://localhost:$LLAMA_ARG_PORT/v1/models"
```

Then, from the Pi Evolving repository:

```bash
./scripts/local-model.sh
./pi.sh /path/to/workspace
```

From PowerShell when Pi Evolving runs through Docker Desktop:

```powershell
.\scripts\local-model.ps1
.\pi.ps1 C:\path\to\workspace
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
`config/models.llamacpp-wsl.json` and reinstall the Pi preset. Never advertise
more context to Pi than llama-server can accept.

The RTX 5090 can also use Blackwell-specific NVFP4 deployments. Unsloth reports
substantially higher speed for that format, but it requires a different serving
stack. This guide deliberately uses GGUF and llama.cpp because the same profile
works across RTX 3090, 4090, and 5090 systems.
