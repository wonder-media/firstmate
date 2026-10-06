# basescout1 report: root files of the demo checkout

## What I did
Ran one command in the worktree `/Users/patrick/.treehouse/demo-a72232/1/demo`
(detached HEAD `a6621f41cecd7ca32b580000e595e90c7c57f4c9`, base branch `release`):

```
ls -la
```

## Output
```
total 24
drwxr-xr-x  6 patrick  staff  192 Oct  6 15:08 .
drwxr-xr-x  4 patrick  staff  128 Oct  6 15:08 ..
drwxr-xr-x  3 patrick  staff   96 Oct  6 15:08 .claude
-rw-r--r--  1 patrick  staff  113 Oct  6 15:08 .git
-rw-r--r--  1 patrick  staff    5 Oct  6 15:08 base.txt
-rw-r--r--  1 patrick  staff    4 Oct  6 15:08 release-only.txt
```

## Findings
Root entries (4):
- `.claude/` - directory
- `.git` - file (worktree pointer, 113 bytes)
- `base.txt` - file, 5 bytes
- `release-only.txt` - file, 4 bytes

`release-only.txt` is present, which is consistent with the checkout being on the `release` base branch.

## Recommendation
None. Nothing needs to ship. No captain decision is open.
