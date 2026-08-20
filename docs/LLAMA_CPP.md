# Building llama.cpp for local models

This guide builds a CUDA-enabled `llama-server` inside Ubuntu on WSL2 and
connects it to Pi Evolving through Docker Desktop.

Primary references:

- [llama.cpp CUDA build instructions](https://github.com/ggml-org/llama.cpp/blob/master/docs/build.md#cuda)
- [llama-server documentation](https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md)
- [NVIDIA CUDA on WSL guide](https://docs.nvidia.com/cuda/wsl-user-guide/)

## Architecture

```text
Pi container
    -> http://host.docker.internal:8080/v1
    -> Windows and WSL2 networking
    -> llama-server in WSL2
    -> local GGUF model on the NVIDIA GPU
```

The commands in this guide run in the WSL2 shell unless marked as PowerShell.

## 1. Prepare WSL2 and CUDA

Install a current NVIDIA Windows driver with WSL2 CUDA support. The Windows
driver provides the CUDA driver to WSL2; do **not** install a Linux NVIDIA
display driver inside WSL2.

From PowerShell, update WSL:

```powershell
wsl.exe --update
```

Inside WSL2, verify that the GPU is visible:

```bash
nvidia-smi
```

Install the basic build tools:

```bash
sudo apt update
sudo apt install -y build-essential cmake git curl
```

A CUDA build also needs the CUDA Toolkit and `nvcc` inside WSL2:

```bash
nvcc --version
```

If `nvcc` is missing, follow NVIDIA's current
[CUDA on WSL installation instructions](https://docs.nvidia.com/cuda/wsl-user-guide/)
and select the WSL-Ubuntu toolkit packages. Do not install the `cuda`,
`cuda-drivers`, or Linux display-driver packages under WSL2; use a
`cuda-toolkit-*` package that does not replace the driver supplied by Windows.

After installing the toolkit, verify both components:

```bash
nvidia-smi
nvcc --version
```

## 2. Clone and build llama.cpp

```bash
mkdir -p ~/gits
cd ~/gits

git clone https://github.com/ggml-org/llama.cpp
cd llama.cpp

cmake -B build -DGGML_CUDA=ON -DCMAKE_BUILD_TYPE=Release
cmake --build build --config Release -j "$(nproc)"
```

The server binary is:

```text
~/gits/llama.cpp/build/bin/llama-server
```

Check the build and detected devices:

```bash
./build/bin/llama-server --version
./build/bin/llama-server --list-devices
```

### Make the commands available on `PATH`

For a source checkout that you expect to rebuild, create user-local symlinks:

```bash
mkdir -p ~/.local/bin

ln -sfn \
  "$HOME/gits/llama.cpp/build/bin/llama-server" \
  "$HOME/.local/bin/llama-server"

ln -sfn \
  "$HOME/gits/llama.cpp/build/bin/llama-cli" \
  "$HOME/.local/bin/llama-cli"
```

Do not copy only the executables. Linux builds use shared llama.cpp and GGML
libraries by default; keeping the commands linked to `build/bin` preserves the
working build layout and avoids stale copies. Rebuilding the same checkout also
updates the commands immediately without another installation step.

Ubuntu normally adds `~/.local/bin` to `PATH` when the directory exists at
login. For the current shell, or if the directory is not already present, run:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

Add that line to `~/.profile` if your login environment does not configure it.
Verify the result:

```bash
command -v llama-server
llama-server --version
llama-cli --version
```

The expected command location is `~/.local/bin/llama-server`. The symlinks
remain valid as long as the source checkout stays at `~/gits/llama.cpp`.

If the build cannot detect the GPU architecture, consult the upstream CUDA
guide for `GGML_NATIVE=OFF` or `CMAKE_CUDA_ARCHITECTURES`. The normal native
build is preferable when compiling on the same GPU that will run the model.

## 3. Choose a GGUF model

Use an instruction-tuned or code-oriented GGUF model with a quantization that
fits your GPU memory. `Q4_K_M` is a common starting point; a larger quantization
usually needs more memory. Model weights, the KV cache, and runtime workspace
all consume VRAM, so file size alone is not the complete requirement.

For an already downloaded model, keep it on the Linux filesystem:

```bash
mkdir -p ~/models
mv /path/to/model.gguf ~/models/
```

llama.cpp can also download a GGUF model from Hugging Face when starting the
server. Its `--hf-repo` option accepts `<organization>/<repository>:<quant>`;
the default quantization is `Q4_K_M`. A gated repository requires `HF_TOKEN`.

## 4. Start the server

For a local GGUF file:

```bash
cd ~/gits/llama.cpp

./build/bin/llama-server \
  --model ~/models/your-model.gguf \
  --alias local-coder \
  --host 0.0.0.0 \
  --port 8080 \
  --api-key local-dev-key \
  --ctx-size 65536 \
  --n-gpu-layers all
```

Or let llama.cpp download a model from Hugging Face:

```bash
./build/bin/llama-server \
  --hf-repo organization/model-GGUF:Q4_K_M \
  --alias local-coder \
  --host 0.0.0.0 \
  --port 8080 \
  --api-key local-dev-key \
  --ctx-size 65536 \
  --n-gpu-layers all
```

These values intentionally match
[`config/models.llamacpp-wsl.json`](../config/models.llamacpp-wsl.json):

| Server option | Pi preset value |
|---|---|
| Model alias | `local-coder` |
| API base URL | `http://host.docker.internal:8080/v1` |
| API key | `local-dev-key` |
| Context window | `65536` |
| API type | `openai-completions` |

`--n-gpu-layers all` requests full GPU offload. Current llama.cpp defaults to
automatic GPU-layer selection, but making the intent explicit is useful when
validating a CUDA setup.

### Security note

Listening on `0.0.0.0` makes WSL2-to-Docker connectivity reliable but can also
make the port reachable through other host interfaces. `local-dev-key` is a
public placeholder, not a secure secret. Do not expose port 8080 to an
untrusted network. Use Windows Firewall, avoid router port forwarding, and use
a private key in both the server command and Pi's persistent `models.json` if
other machines can reach the port.

Do not enable llama-server's filesystem or agent tools for this integration;
Pi needs only the model API.

## 5. Verify the server

Wait until the server reports that the model is loaded. In another WSL2 shell:

```bash
curl --fail \
  -H 'Authorization: Bearer local-dev-key' \
  http://localhost:8080/v1/health

curl --fail \
  -H 'Authorization: Bearer local-dev-key' \
  http://localhost:8080/v1/models
```

Test a completion directly:

```bash
curl --fail http://localhost:8080/v1/chat/completions \
  -H 'Authorization: Bearer local-dev-key' \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "local-coder",
    "messages": [{"role": "user", "content": "Reply with the word ready."}],
    "max_tokens": 16
  }'
```

From Windows PowerShell, verify WSL2 localhost forwarding:

```powershell
curl.exe `
  -H "Authorization: Bearer local-dev-key" `
  http://localhost:8080/v1/models
```

Then verify the route used by the Pi container:

```powershell
.\shell.ps1
```

Inside the container:

```bash
curl --fail \
  -H 'Authorization: Bearer local-dev-key' \
  http://host.docker.internal:8080/v1/models | jq .
exit
```

## 6. Enable the model in Pi Evolving

From PowerShell in the Pi Evolving repository:

```powershell
.\scripts\local-model.ps1
.\pi.ps1 $workspace
```

The first command checks connectivity, backs up any existing persistent model
configuration, installs the tracked llama.cpp preset, and selects
`llamacpp-wsl/local-coder` in `.env`.

Linux/WSL users can run:

```bash
./scripts/local-model.sh
./pi.sh /path/to/workspace
```

Use `-SkipCheck` in PowerShell or `--skip-check` in Bash only when you
intentionally want to install the preset while llama-server is stopped.

## Context size and memory

The server's `--ctx-size` is the real allocated context capacity. The
`contextWindow` in Pi's model configuration describes that capacity to Pi; it
does not increase the server allocation.

If `65536` causes an out-of-memory error:

1. reduce `--ctx-size`, for example to `32768` or `16384`;
2. change `contextWindow` in `config/models.llamacpp-wsl.json` to the same value;
3. rerun `.\scripts\local-model.ps1` to install the updated preset;
4. use a smaller model or a more compact quantization if necessary.

Avoid advertising a larger context to Pi than the server can actually accept.

## Updating and rebuilding llama.cpp

Stop `llama-server`, then:

```bash
cd ~/gits/llama.cpp
git status
git pull --ff-only
cmake -B build -DGGML_CUDA=ON -DCMAKE_BUILD_TYPE=Release
cmake --build build --config Release -j "$(nproc)"
```

Restart the server and repeat the health and model-list checks.

## Troubleshooting

### `nvcc: command not found`

Install the CUDA Toolkit for WSL-Ubuntu. If it is installed outside the normal
path, ensure its `bin` directory is on `PATH`. Do not install a Linux NVIDIA
display driver inside WSL2.

### CMake cannot find CUDA

Confirm `nvcc --version`, remove a stale non-CUDA build directory if necessary,
and configure again with `-DGGML_CUDA=ON`. If multiple toolkits are installed,
the upstream build guide documents `CMAKE_CUDA_COMPILER`.

### The GPU is detected but VRAM usage stays low

Start with `--n-gpu-layers all`, inspect the llama-server startup log, and watch
the GPU from another WSL2 terminal:

```bash
watch -n 1 nvidia-smi
```

### CUDA out of memory

Reduce context size, choose a smaller model or quantization, or allow fewer GPU
layers. Unified-memory fallback exists but is slower and is not the preferred
first fix.

### Windows can reach the server but Docker cannot

Confirm that the server uses `--host 0.0.0.0`, then check Windows Firewall and
Docker Desktop networking. The preferred container URL is
`http://host.docker.internal:8080/v1`; using WSL2's changing IP address should
be a last resort.

### HTTP 401

The key passed to `--api-key` must match the key in Pi's persistent
`models.json`. Re-run the local-model installer after changing the tracked
preset.
