# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

Two files that produce the `bota87/bitcoind` Docker Hub image: a [Dockerfile](Dockerfile) that verifies and unpacks the official Bitcoin Core release tarball onto Debian slim, and a [GitHub Actions workflow](.github/workflows/build-image.yml) that builds and pushes it. No application code, no tests, no build script.

## Publishing a version does not require a commit

The workflow is `workflow_dispatch` with a **`version` text field**. That value feeds both the `BITCOIN_VERSION` build-arg and the Docker tag, so a new Bitcoin Core release is published by typing it in the GitHub UI — nothing in the repo changes.

```bash
gh workflow run build-image.yml -f version=29.4 -f latest=true
```

Do not "bump the version" by editing files. The `ARG BITCOIN_VERSION` default in the Dockerfile is a **fallback for local `docker build .` only** and is deliberately allowed to lag; it never affects what gets published.

The `latest` checkbox (default on) controls whether `bota87/bitcoind:latest` is moved. Uncheck it when building a maintenance release of an older branch — as of writing, `latest` tracks 29.x while Bitcoin Core is on 31.x, so building an old branch with it checked would drag `latest` backwards.

## Supply-chain verification is the point of the Dockerfile

Binaries are installed only after the release's `SHA256SUMS` passes a **GPG signature check against pinned builder fingerprints**, then the tarball's own hash is checked against that file. Both are in one `RUN`; `gnupg` is installed and purged in the same layer so it never reaches the image.

The `BITCOIN_SIGNERS` build-arg holds `<guix.sigs-filename>:<primary-key-fingerprint>` pairs. The flow matters: the key file is fetched from `bitcoin-core/guix.sigs`, its fingerprint is checked with `gpg --show-keys` **before** import, and only then is it imported. Importing first and checking after would leave a rogue key in the keyring able to produce a `GOODSIG`.

`BITCOIN_MIN_SIGS` (currently 4) is the threshold, counted by parsing `GOODSIG` from `--status-fd` — `gpg --verify`'s exit code is not reliable when a file carries many signatures (29.4 carries 13).

### Changing the pinned set

The threshold and the key set are one decision, not two: a threshold above the set's **floor** — the fewest `GOODSIG` any legitimate release produces — silently converts into "no release can be built". Measured over 26.2 → 31.1 the current set's floor is 5 (7 from 29.0 on), so 4 holds margin. Re-measure before touching either.

Rank candidates by **`GOODSIG`, never by "has signed"**. An expired key emits `EXPKEYSIG`, which is not counted, so it contributes nothing while still appearing among the signers — glozow appears in 10 of 16 releases and is worth exactly zero. Ranking by signature presence puts dead keys in the set and quietly lowers the real floor.

**Never write fingerprints from memory.** Derive them: import candidates into a scratch `GNUPGHOME`, verify a real `SHA256SUMS.asc`, and read the primary fingerprint from the trailing field of each `VALIDSIG` line — it differs from the signing key's own fingerprint for several builders (fanquake signs with a `bitcoin-otc` key, not the fingerprint most references list).

Note that `VALIDSIG` covers both good and expired signatures, so counting it overstates the floor; the Dockerfile counts `GOODSIG`, and any measurement must match.

## Architectures

`platforms: linux/amd64,linux/arm64`. `linux/arm/v7` was deliberately removed — an unrecognised `TARGETPLATFORM` now fails the build loudly rather than composing a broken URL. Emulated builds are cheap here because the `RUN` steps download and unpack rather than compile.

## Two things that look like omissions but are not

- **No `actions/checkout`.** `build-push-action` falls back to the remote Git context and builds the Dockerfile committed on the branch. Adding a checkout requires also setting `context: .`, or the build breaks.
- **Bash completions are fetched with `curl`, not `ADD`.** `ADD` from a URL bypasses layer caching and writes mode `0600` — a latent trap if the image ever stops running as root.

Completions come from the `v${BITCOIN_VERSION}` tag, not `master`, so they match the shipped binaries. The consequence: a version string with no matching Git tag fails the build instead of silently falling back.

## Conventions

Commit messages in this repo are written in Italian.
