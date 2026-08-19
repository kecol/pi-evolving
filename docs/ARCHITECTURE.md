# Architecture

Pi Evolving separates execution, work, implementation, runtime state, and
lineage so each has clear persistence and trust boundaries.

```text
                 Docker image
       Node 24 · npm · uv · Git · build tools
                         |
       +-----------------+-----------------+
       |                 |                 |
 /workspace            /pi        /home/pi/.pi-agent
 host project      source volume      state volume
       |                 |                 |
       +------ task pressure               |
                         |                 |
                  tested evolution --------+
                         |
                    /evolution
                   lineage volume
```

## The five domains

- The image is the replaceable Generation 0 substrate. It contains acquisition
  and build mechanisms, not every possible project dependency.
- `/workspace` is the current host project. Changing workspaces does not change
  the Pi lineage.
- `/pi` is a Linux-native named volume containing the canonical upstream clone,
  its `.git` directory, `node_modules`, and build outputs.
- `/home/pi/.pi-agent` persists settings, sessions, auth metadata, and acquired
  executables. Its `bin` directory is first on `PATH`.
- `/evolution` stores generation records, observations, and test evaluations.

Source and runtime state are separate because source belongs in inspectable Git
history while sessions, authentication, and downloaded tools must never be
committed there.

## Why a named source volume

Unix permission behavior, executable bits, npm installs, Vite/Vitest temporary
files, and file watchers are unreliable on some Windows-backed bind mounts.
The default `pi-evolving-source` volume keeps `/pi` on Docker's Linux-native
filesystem. The user's workspace may still be a Windows bind mount.

## Why run from source

The image does not install Pi globally. `/pi/pi-test.sh` launches the persistent
checkout, and upstream's own `npm install --ignore-scripts`, build, check, and
test paths validate it. Removing a container therefore cannot erase a
self-change.

## Process and permission model

Pi runs as the unprivileged `pi` user (default UID/GID 1001) so permission tests
remain meaningful. A root bootstrap container only fixes volume ownership.
`tini` is PID 1 for correct signal forwarding and child reaping.

The Docker socket is deliberately absent. Pi cannot silently control the host
daemon; a broadly useful system dependency becomes a reviewed Dockerfile change
for the next environment generation.
