# Troubleshooting

## Docker is unavailable

Run `docker version`. The scripts require a reachable Docker daemon and Compose
v2 (`docker compose`), but do not require Docker Desktop specifically.

## `fd` not found

Pi may acquire fd only on its first interactive launch. Start Pi, then check in
`./shell.sh` or `.\shell.ps1`:

```bash
echo "$PATH"
fd --version
```

`/home/pi/.pi-agent/bin` must appear on `PATH`. Do not install Debian's older
`fd-find`; it may lack `--no-require-git`.

## Git reports dubious ownership

The image configures `/pi` as a system safe directory. If the warning remains,
rebuild the image and inspect `id` and `ls -ld /pi` in a maintenance shell.
Setup's ownership phase should make the volume writable by `pi`.

## Permission denied under `.pi-agent`

Check:

```bash
id
ls -ld /home/pi/.pi-agent /home/pi/.pi-agent/bin
```

Rerun setup to repair named-volume ownership. Avoid running npm or Pi manually
as root.

## npm, Vite, chmod, or EPERM failures

Ensure `/pi` is the `pi-evolving-source` named volume, not a Windows-backed
bind mount. Windows-hosted workspaces are supported, but Pi's own source needs
Linux-native filesystem semantics.

## WSL clipboard test failures

Two clipboard tests failed in the historical WSL2 baseline because Pi detected
WSL through `/proc/version`. Compare names and counts with
[Generation 0](GENERATION_0.md); do not modify tests merely to hide this
environment distinction.

## Root-owned `node_modules`

Old root-run installations can leave unwritable files. Back up `/pi`, use the
confirmed source reset if necessary, and rerun setup. A less destructive repair
is to enter a one-off root container, correct `/pi` ownership, then reinstall as
`pi`; setup already performs the ownership correction.

## Port 9191 is already in use

Change `PI_HOST_PORT` in `.env`. The launcher binds the configured port only to
`127.0.0.1`, not the LAN.
