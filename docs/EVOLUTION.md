# Evolution model

Evolution is a response to useful work:

```text
workspace task -> observed friction -> candidate adaptation
              -> test and compare -> retain or revert -> continue task
```

Starting with “improve yourself” supplies weak evidence. A better first task is
to implement a real feature and permit inspection of `/pi` only when concrete
limitations interfere.

## Pick the smallest useful layer

Useful adaptation often happens outside Pi core. Prefer, in order:

1. a direct solution in the current project;
2. a project helper or workflow;
3. a reusable instruction, skill, extension, or user-level tool;
4. a harness/workflow improvement;
5. a focused Pi core change;
6. a reviewed Docker environment change.

Before a `/pi` edit, state the observed friction, recurrence likelihood,
missing capability, and expected observable improvement.

## Self-edit workflow

Inspect the implementation and Git status, make the narrowest change, run the
narrowest relevant tests, then run `npm run check` and broader tests when the
impact warrants it. Compare results with the recorded baseline, inspect the
diff, and commit separately with an `evolve:` prefix. Never mix `/workspace`
and `/pi` changes in one commit.

Code already loaded in a process does not change retroactively:

```text
Pi_n -> edits and validates /pi -> restart -> Pi_(n+1)
```

Generation 0 is the upstream baseline plus harness initialization. Increment a
generation only for an accepted Pi commit, reusable agent capability, or
meaningful environment change—not for ordinary project edits. V1 intentionally
leaves later generation records manual.

## Git lineage and upstream

`origin/main` is upstream; `evolve` is local lineage. The update commands fetch
and display available commits without integration. An explicit `--rebase` or
`-Rebase` requires a clean tree, rebases onto `origin/main`, reinstalls,
rebuilds, and checks. The harness never automatically pushes.

Test failures are evidence, not obstacles to edit away. New failures are
suspicious; known baseline failures disappearing also deserve investigation.

## Future candidate worktrees

A later version can evaluate changes transactionally without disturbing the
active checkout:

```bash
git -C /pi worktree add /tmp/pi-candidate -b candidate/<name>
```

The current generation could modify, build, test, and score that candidate,
then accept or discard it. V1 avoids an automatic scheduler or genetic loop.
