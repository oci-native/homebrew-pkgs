# Contributing

## Setup

Tap the repo, then work in the tap clone directly; that way `brew` commands see your
changes without extra wiring:

```sh
brew tap oci-native/pkgs
cd "$(brew --repository oci-native/pkgs)"
git checkout -b my-change
```

## Adding a native cask

1. Create `Casks/<first-letter>/<token>.rb` (homebrew-cask layout, token named after
   the upstream package).
2. Point `url` at the official upstream artifact. Take `sha256` from the vendor's
   published checksums where available; apt `Packages` indexes already carry them.
3. Add a `livecheck` block so the autobump workflow can track it.
4. Handle arch explicitly: `depends_on arch: :x86_64` when upstream is amd64-only, or
   `arch arm: ..., intel: ...` with `arm64_linux:`/`x86_64_linux:` sha keys when both
   are published.

Use `Casks/s/signal-desktop.rb` as the template for the `.deb` unpack pattern.

## Adding an OCI cask

Read [docs/oci-casks.md](docs/oci-casks.md) first; it covers the launcher contract,
the `cask.deb` convention, and versioning. In short:

1. Write `containers/<app>/Containerfile`. Pin the base image tag; Renovate bumps it.
2. Copy `Casks/z/zoom-oci.rb` (deb-based) or `Casks/g/galculator.rb` (packages from
   base) as the template. The launcher's image tag comes from the cask `version`.
3. Test the container by hand with the socket and device mounts from the launcher
   before wiring the cask.

## Verify before opening a PR

```sh
brew style --cask oci-native/pkgs/<token>
brew audit --strict --online --cask oci-native/pkgs/<token>
brew livecheck --cask oci-native/pkgs/<token>
brew install --cask oci-native/pkgs/<token>   # and launch it
brew uninstall --cask oci-native/pkgs/<token>
```

## Commits and PRs

- Conventional commit messages (`feat(cask): ...`, `fix(ci): ...`).
- Sign off your commits (`git commit -s`, DCO).
- One concern per PR. Split unrelated changes; stack dependent ones.
