# Phase 10 — Own multi-arch images (Improvement 9) — **re-scoped**

Spec: SPEC Section 15, Section 17 (Phase 10), ADR-013 (GitHub Actions stays off). Read first: `docs/ADOPT.md`, `docs/PROGRESS.md`. **Status: planned, not started. Open question 1 below decides how big this phase is: ask the owner first.**

## New finding (4 Oct 2026, checked from the pinned code and the registry)
The SPEC assumed Chatwoot's official images are amd64-only, so we would have to build our own arm64 image (needed for cheap/free ARM servers such as Oracle Always Free). **That is outdated for v4.18.0:**
- Chatwoot's own workflow `.github/workflows/publish_foss_docker.yml` builds both `linux/amd64` and `linux/arm64` and publishes a combined manifest, and it **strips `enterprise/` and `spec/enterprise/` and sets `CW_EDITION=ce`** before building the `-ce` image.
- `docker manifest inspect chatwoot/chatwoot:v4.18.0-ce` lists an `amd64` and an `arm64` entry (plus a build-attestation entry).
So the official CE image should already run on ARM and already be Community-Edition-only. **What is NOT verified:** that it actually boots, migrates and runs our stack on a real arm64 machine (cannot be done in the cloud sandbox without ARM or emulation), and that older tags we may pin later also have arm64.

## What this phase is, in plain words
Originally: build and publish our own server images through GitHub Actions. Now probably: **do not build anything**; prove the official image works on ARM, make our tools able to pin images by their exact fingerprint (digest) for safety, and write down the decision. Building our own image stays an option only if the official one turns out not to be good enough.

## Open questions for the owner (plain words; defaults in bold)
1. **Own images or the official ones?** **Default A: use the official multi-arch CE image** (nothing to build, no GitHub Actions needed, stays the same as Chatwoot's tested image). Option B: still build our own image with GitHub Actions + GHCR (needs Actions switched on and Chatwoot's own scheduled workflows disabled one by one; more work, more things to maintain; only worth it if you want to ship fixes before Chatwoot does). Option C: build by hand on your own laptop with `docker buildx` and push to GHCR when needed (no Actions).
2. **Pin by digest?** **Default: yes, optional per client**: `install.image_digest` makes deploy/upgrade use the exact fingerprint of the tested image, so a re-tagged image can never silently change a client's server.

## Tasks (default A; B/C tasks only if chosen)

### [ ] 10.1 — Record the finding and decide (ADR)
- **Goal:** ADR-018 "Use official multi-arch CE images" (or the owner's alternative); add the finding to `docs/EXPLORATION_REPORT.md`; with the owner's approval correct SPEC section 15 and Appendix A rows R1/R6; tick off this phase's scope.
- **Acceptance:** ADR and report written; SPEC edits only with approval.

### [ ] 10.2 — Verify the official image's contents and platforms
- **Goal:** `docker buildx imagetools inspect` (or `manifest inspect`) for the pinned tag and for the tags `opskit upgrade` will use; confirm `amd64` and `arm64` are present; confirm there is no `enterprise/` directory in the image (`docker run --rm --entrypoint sh <image> -c 'test ! -d /app/enterprise'`) and that licensing features are the CE ones; record digests.
- **Acceptance:** results in EXPLORATION_REPORT; a small `opskit` check (`opskit image check <tag>`) that repeats this and fails loudly if a tag lacks arm64 or contains `enterprise/`.

### [ ] 10.3 — Digest pinning
- **Goal:** `client.yaml install.image_digest` (optional), rendering `chatwoot/chatwoot@sha256:...` in the compose file; `opskit upgrade` resolves and records the digest of the target tag in its history and in the client's config; rollback restores the previous digest.
- **Acceptance:** bats (render, upgrade, rollback with fake docker); one live upgrade rehearsal on the demo.

### [ ] 10.4 — ARM boot test (as far as the environment allows)
- **Goal:** try to boot the official arm64 image under emulation (QEMU/binfmt) in the sandbox for a smoke test (boot, `db:chatwoot_prepare` on an empty database, `/api` health). Installing emulation is a new tool: ask the owner first. If emulation is not possible, this is deferred to the real ARM server in Phase 11 and recorded as NOT VERIFIED.
- **Acceptance:** result recorded either way.

### [ ] 10.5+ — Only if the owner picks B or C
- **Goal (B):** `opskit-image.yml` (build from the pinned tag, strip `enterprise/`, `buildx` amd64+arm64, push to GHCR with our own tag scheme, smoke test), the steps to enable Actions safely (disable Chatwoot's workflows individually; ledger row for any workflow edits), image signing/provenance notes. **(C):** a documented script `opskit/bin/build-image` for local buildx and a manual push.
- **Acceptance:** an image published, pulled and booted by the demo client; no enterprise code in it.

## Not in this phase
Changing Chatwoot's code, forking its Dockerfile beyond what the official build already does, a private registry.
