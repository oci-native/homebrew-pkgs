# homebrew-pkgs

A [Homebrew](https://brew.sh) tap that installs Linux desktop apps with proper desktop
integration: a `.desktop` entry your launcher can see, an icon, and a binary on your
`PATH`. Homebrew tracks every file, so `brew uninstall` removes all of it.

## Install

```sh
brew tap oci-native/pkgs
brew install --cask signal-desktop
```

Or in one step:

```sh
brew install --cask oci-native/pkgs/signal-desktop
```

## Casks

| Cask | App | Type | Source | Arch |
| --- | --- | --- | --- | --- |
| `signal-desktop` | [Signal](https://signal.org/) | native | official apt pool `.deb` | x86_64 |
| `signal-oci` | [Signal](https://signal.org/) | OCI container | official apt pool `.deb` | x86_64 |
| `zoom-oci` | [Zoom](https://zoom.us/) | OCI container | official `.deb` from cdn.zoom.us | x86_64 |
| `galculator` | [Galculator](https://github.com/galculator/galculator) | OCI container | alpine package | x86_64 |

Native casks unpack the vendor artifact onto the host. OCI casks build a container
image locally on first launch and run the app in it with podman or docker, with a
native window, GPU, audio, microphone, and camera wired through. Both kinds give you
a launcher entry, an icon, and a binary on `PATH`.

## How it works

Vendors ship Linux desktop apps as `.deb` packages or AppImages. Each cask here turns one
of those into a normal Homebrew install without touching the system package manager. The
artifact comes from the official upstream URL and is pinned by `sha256`. For `.deb`
payloads, sandboxed `preflight_steps` unpack the archive with `bsdtar`, so the same cask
works on any distro, Debian or not. The app binary is linked into the Homebrew prefix.
The `.desktop` entry (with `Exec` rewritten to the brew path) and the icon go under
`~/.local/share`, which is where launchers, docks, and app grids look.

OCI casks work differently: the cask installs a launcher that pulls the app's image
from `8gcr.container-registry.dev/oci-native` on first run, falling back to building
it from a Containerfile in this repo when the pull fails (the install prints the
Containerfile so you see the recipe), then runs it in a rootless container with the
display, GPU, and audio/video devices mounted. Published images are signed with
cosign, and each cask pins the signed digest, so a pinned launcher pulls by
`@sha256:...` rather than by tag. Set `OCI_NATIVE_REGISTRY` to use another registry,
or `OCI_NATIVE_BUILD=1` to always build locally. The design is documented in
[docs/oci-casks.md](docs/oci-casks.md).

`brew uninstall --cask <name>` removes the binary link, desktop entry, and icon. `zap`
also clears the app's user data if you ask for it.

## Staying up to date

Casks carry `livecheck` blocks pointing at their upstream release channel. A scheduled
workflow runs [`brew bump`](https://docs.brew.sh/Manpage#bump-options-formulacask-), the
same tool
[Homebrew/homebrew-cask runs on its own casks](https://github.com/Homebrew/homebrew-cask/blob/main/.github/workflows/autobump.yml),
inside the `ghcr.io/homebrew/brew` container. When a cask falls behind, the workflow
opens a PR with the new version and `sha256`. A separate Renovate workflow bumps the
base image tags in the Containerfiles. As a user you only run:

```sh
brew update && brew upgrade
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for the cask conventions and the verification
checklist, and [SECURITY.md](SECURITY.md) for reporting vulnerabilities.

## Requirements

- Linux, x86_64 (per-cask arch support noted in the table above)
- [Homebrew on Linux](https://docs.brew.sh/Homebrew-on-Linux)
- podman or docker, for the OCI casks

## License

[Apache-2.0](LICENSE)
