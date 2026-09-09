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

| Cask | App | Source | Arch |
| --- | --- | --- | --- |
| `signal-desktop` | [Signal](https://signal.org/) | official apt pool `.deb` | x86_64 |

## How it works

Vendors ship Linux desktop apps as `.deb` packages or AppImages. Each cask here turns one
of those into a normal Homebrew install without touching the system package manager. The
artifact comes from the official upstream URL and is pinned by `sha256`. For `.deb`
payloads, sandboxed `preflight_steps` unpack the archive with `bsdtar`, so the same cask
works on any distro, Debian or not. The app binary is linked into the Homebrew prefix.
The `.desktop` entry (with `Exec` rewritten to the brew path) and the icon go under
`~/.local/share`, which is where launchers, docks, and app grids look.

`brew uninstall --cask <name>` removes the binary link, desktop entry, and icon. `zap`
also clears the app's user data if you ask for it.

## Staying up to date

Casks carry `livecheck` blocks pointing at their upstream release channel. A scheduled
workflow runs [`brew bump`](https://docs.brew.sh/Manpage#bump-options-formulacask-), the
same tool
[Homebrew/homebrew-cask runs on its own casks](https://github.com/Homebrew/homebrew-cask/blob/main/.github/workflows/autobump.yml),
inside the `ghcr.io/homebrew/brew` container. When a cask falls behind, the workflow
opens a PR with the new version and `sha256`. As a user you only run:

```sh
brew update && brew upgrade
```

## Adding a cask

1. Create `Casks/<first-letter>/<token>.rb` (homebrew-cask layout, token named after the
   upstream package).
2. Point `url` at the official upstream artifact. Take `sha256` from the vendor's
   published checksums where available; apt `Packages` indexes already carry them.
3. Add a `livecheck` block so autobump can track it.
4. Handle arch explicitly: `depends_on arch: :x86_64` when upstream is amd64-only, or
   `arch arm: ..., intel: ...` with `arm64_linux:`/`x86_64_linux:` sha keys when both are
   published.
5. Verify before opening a PR:

   ```sh
   brew style --cask oci-native/pkgs/<token>
   brew audit --strict --online --cask oci-native/pkgs/<token>
   brew install --cask oci-native/pkgs/<token>
   ```

## Requirements

- Linux, x86_64 (per-cask arch support noted in the table above)
- [Homebrew on Linux](https://docs.brew.sh/Homebrew-on-Linux)

## License

[Apache-2.0](LICENSE)
