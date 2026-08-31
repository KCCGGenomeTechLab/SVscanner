# Releasing SVscanner

The release number lives in exactly one place: the [`VERSION`](../VERSION) file at the
repository root, as a bare `X.Y.Z`. Edit it by hand when cutting a release.

| Where the version appears | How it stays correct |
|---|---|
| `VERSION` | Source of truth, edited by hand. |
| `scripts/run_workflow.sh` (`--version`, run banner) | Reads `VERSION` at startup. Never hardcode it. |
| git tag `vX.Y.Z` | Must match `VERSION` at the tagged commit — checked by CI and by the pre-push hook. |
| `README.md` (`module load SVscanner/X.Y.Z`) | The version installed as an if89 module, which is not built for every tag. Checked as a warning only. |

## Cutting a release

**Bump `VERSION` before the release commit is merged** — the tag is only correct if the
commit it points at already carries the new number.

```bash
# 1. Edit VERSION to the new number and commit it.
vi VERSION
git commit -am "release v0.6.1"
git push origin dev
```

2. Merge `dev` into `main` as usual.

3. Create the tag and release on the GitHub website
   (*Releases → Draft a new release → Choose a tag → Create new tag*), targeting that
   merge commit. Name the tag `v0.6.1`.

4. **Check the `version check` run** under the Actions tab. Publishing the release
   fires it against the new tag; if it fails, the tag disagrees with `VERSION` and the
   release needs re-cutting (delete the release and its tag, fix `VERSION`, tag again).

5. Install that version as an if89 module on Gadi and confirm the deployed copy
   reports what you expect:

```bash
module use -a /g/data/if89/apps/modulefiles
module load SVscanner/0.6.1
svscanner --version          # must print: SVscanner v0.6.1
```

6. Update the `module load SVscanner/X.Y.Z` lines in the README to that version, now
   that the module actually exists.

## The two checks

Both run [`check_version.sh`](../scripts/check_version.sh), which reads files straight
out of a commit — nothing is checked out and the working tree is untouched.

**[CI](../.github/workflows/version-check.yml)** — runs on every branch push, pull
request and tag push. This is the one that covers tags created on the GitHub website,
which never reach a local hook. It reports *after* the tag exists, so treat a red
`version check` on a tag as "re-cut this release".

**[`.githooks/pre-push`](../.githooks/pre-push)** — refuses the push before anything
leaves your machine, for tags pushed from the command line. Enable once per clone:

```bash
git config core.hooksPath .githooks
```

`core.hooksPath` is local to each clone, so a fresh clone needs this again.
`git push --no-verify` bypasses it.

### What counts as a failure

Hard errors, which fail CI and block a local push:

- a tag `vX.Y.Z` published on a commit whose `VERSION` does not say `X.Y.Z` — the
  mistake that produced a v0.6.0 tag on a 0.5.2 script;
- `VERSION` missing or malformed;
- `run_workflow.sh` hardcoding a version instead of reading `VERSION`.

Warning only, never blocking:

- the README's `module load` version differing from `VERSION`, since the if89 module
  lags the repository between deployments.

Commits from before the `VERSION` file existed are skipped, so old branches still push.

## Checking by hand

```bash
scripts/check_version.sh                 # the working tree
scripts/check_version.sh --rev <commit>  # any commit, without checking it out
scripts/check_version.sh --expect 0.6.1  # as CI does for tag v0.6.1
```

Only `module load SVscanner/<version>` lines in the README are compared, so prose that
deliberately names an older release — such as the note that versions before `0.5.2`
sized themselves from the whole compute node — is left alone.
