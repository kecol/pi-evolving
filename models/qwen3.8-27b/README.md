# Qwen3.8-27B profile

This profile deploys the quantized Unsloth `UD-Q4_K_XL` GGUF through
llama.cpp. It is the explicit first-run model selected by:

```bash
./setup.sh --model qwen3.8-27b
```

```powershell
.\setup.ps1 -Model qwen3.8-27b
```

The setup command expects a compatible llama-server to be running already. Use
the scripts under `scripts/models/qwen3.8-27b` to download, serve, and check the
model. All bundled llama.cpp presets use port `18080` to avoid common web-server
collisions on port 8080. See
[the full deployment guide](../../docs/QWEN38_27B.md) for hardware, memory, and
WSL2 guidance.
