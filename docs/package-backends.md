# RFC: package backends beyond deb and pkg

Status: draft. This records options and trade-offs so we can decide with data
instead of vibes.

## Where this tap sits

The target stack is an arch host, homebrew as the app manager, and flox for
per-project dev environments. Those three cover the host well. The gap sits
elsewhere: a growing class of GUI apps is built and shipped container-first
(vendor images, linuxserver.io-style packaging), and nothing on a normal desktop
serves them as normal apps. No desktop entry, no launcher presence, no icon; you
get a `docker run` incantation in a README instead.

That gap is this tap's job. The launcher contract, the mount matrix, and the
desktop-entry wiring already turn a container into something walker launches
like any native app. The question this RFC asks is where the payloads should
come from as the tap grows past hand-hunted debs and arch packages.

## Backend options

### A. Upstream container images as casks

For apps whose upstream already publishes an OCI image, skip the Containerfile
entirely. The cask pins the upstream image by digest, and the launcher pulls and
runs it with our usual mounts and a desktop entry.

This is the shortest path to the actual gap: container-first apps served as
normal apps. Adding one becomes a launcher script and a digest. Livecheck can
query the registry's tag list API, and version-to-digest resolution is one
`skopeo inspect` away.

Trade-offs: we inherit upstream's image contents wholesale, so the trust chain
is "whatever the vendor put in the image", pinned by digest rather than by a
sha256 we computed from a vendor artifact. That is the same trust level as
running their image by hand, with pinning added on top. Images that expect
linuxserver's s6 init or PUID/PGID conventions need those honored in the
launcher.

### B. Nix inside the container

A Containerfile starting `FROM docker.io/nixos/nix`, a pinned nixpkgs revision,
and `nix profile install nixpkgs#<pkg>`. Nix becomes a fourth base next to
debian, alpine, and arch, and adding an app shrinks to naming the package.

Nixpkgs brings roughly 100k packages, every input hash-pinned, and a public
binary cache, so "building" is mostly downloads. A pinned revision also produces
the same closure on every machine, which fixes a trade-off SECURITY.md currently
admits to: our distro-based images resolve packages at build time and can
diverge between machines.

Downsides: the nixos/nix base is heavy, and each app image carries its own
glibc, mesa, and toolkit. A multi-stage build fixes the weight (stage one
realizes the closure, stage two copies just the `/nix/store` paths onto a
minimal base) and still runs with plain `podman build` on the client.

### C. Shared nix store volume

One host volume mounted into every nix-based container so closures deduplicate
across apps. Right answer if we ever run many nix apps, but it moves payload
integrity from brew's sha256 to nix's hash model and makes images stateful.
Shelved until dedup would actually matter.

### D. nix bundle to AppImage

Build AppImages from nixpkgs in CI, ship them as native `app_image` casks.
Rejected: it needs hosting for the built artifacts, and this tap's rule is that
the registry is an optional cache, never a requirement.

## Where flox fits

Flox wraps nix in a brew-shaped CLI with a manifest and lockfile, and on this
stack it earns its keep as the dev-environment layer: per-project toolchains,
`flox activate`, done. It is part of the host stack, not a competitor to the
tap.

It is not the app-serving layer, though. `flox containerize` can export an
environment as a minimal runtime image, but it runs on the host, which would
make flox a client dependency for image builds and break the "client needs only
brew and a container engine" contract. It also adds the flox catalog as a third
party in the trust chain. The minimal-image result it produces is the same
thing option B's multi-stage build yields with no new dependencies. Dev
environments: yes. App packaging: no.

## Risks and open questions

- Option A auth and rate limits: docker.io anonymous pulls are rate-limited;
  ghcr and lscr are friendlier. Worth preferring non-dockerhub sources where
  upstream offers them.
- Option A desktop integration: container-first apps vary wildly in how they
  expect display, audio, and config to arrive. The existing mount matrix covers
  the common cases; each app still needs hand-testing.
- Option B GL: nixpkgs mesa inside the container plus the `/dev/dri` mount
  should work, since the whole userland is nix and there is no host library
  mismatch (the nixGL problem only bites on foreign hosts). Unverified.
- Option B unfree packages (zoom, brave): not in the binary cache, so nix
  fetches the vendor binary itself under `NIXPKGS_ALLOW_UNFREE`. Still pinned,
  just a slower first build.
- Livecheck for B: the installable version is whatever the pinned revision
  carries. nixhub.io maps versions to nixpkgs revisions and could back a
  livecheck; Renovate could bump the pin. Neither is wired up.

## Recommendation

Option A is the one that serves the tap's actual purpose and should go first:
pick one container-first GUI app with a well-maintained upstream image, wrap it
with the launcher and a digest-pinned cask, and see how much of the existing
contract transfers. Option B waits until an app shows up that arch and debian
both serve badly, then gets prototyped with the multi-stage build and measured
for size and first-run time. C stays shelved, D stays rejected, and flox stays
on the host as the dev-environment layer.
