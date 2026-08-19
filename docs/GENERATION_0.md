# Generation 0

Generation 0 is an upstream Pi checkout on `evolve`, built in the initial
container substrate and accompanied by its first metadata record.

## Historical reference

The original validated environment used:

- Pi v0.84.2
- Node 24 and uv
- non-root user `pi`
- Linux-native Docker volumes for `/pi` and `~/.pi-agent`
- fd 10.4.2 acquired into `~/.pi-agent/bin`
- build: pass
- check: pass
- Docker Desktop/WSL2 coding-agent tests: 1938 passed, 49 skipped, 2 failed

The two failures were `readClipboardImage` non-Wayland clipboard cases. The
container's `/proc/version` contained `microsoft-standard-WSL2`, causing Pi to
select its WSL clipboard path even after ordinary WSL environment variables
were removed by the tests.

These numbers are historical controls, not universal expectations. Native
Linux and newer Pi versions can differ. Do not encode them as permanent pass
criteria.

Run your own baseline with:

```bash
./test.sh
```

or:

```powershell
.\test.ps1
```

The command records full logs and a JSON summary in
`/evolution/evaluations`. Setup records immutable initialization facts in
`/evolution/generations/generation-0000.json` and sets `/evolution/CURRENT` to
`0`. If fd is absent, launch Pi once so its tool manager can acquire a current
version, then rerun the baseline.
