# homebrew-pkgs

A [Homebrew](https://brew.sh) tap of **Linux desktop apps installed the native way** — real
`.desktop` entries, icons, and binaries on your `PATH`, managed entirely by `brew`.

No fighting the distro. No copying files around by hand. `brew install`, and the app shows
up in your launcher like it was always there. `brew uninstall`, and it's gone without a trace.

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

Upstream vendors ship Linux desktop apps as `.deb` packages or AppImages. Each cask here
turns one of those into a native-feeling install without touching the system package
manager:

- the artifact is fetched from the **official upstream URL** and pinned by `sha256`
- `.deb` payloads are unpacked by sandboxed `preflight_steps` (no `dpkg` needed, works on
  any distro)
- the binary is linked into the Homebrew prefix, so it is on your `PATH`
- the `.desktop` entry (with `Exec` rewritten to the brew prefix) and icon land under
  `~/.local/share`, so app launchers, docks, and grids pick the app up like a distro
  package would

Everything is tracked by Homebrew, so `brew uninstall --cask <name>` removes the binary
link, desktop entry, and icon cleanly, and `zap` clears app data on request.

## Staying up to date

Casks carry `livecheck` blocks pointing at their upstream release channel. A scheduled
workflow runs [`brew bump`](https://docs.brew.sh/Manpage#bump-options-formulacask-)
— the same machinery
[Homebrew/homebrew-cask uses](https://github.com/Homebrew/homebrew-cask/blob/main/.github/workflows/autobump.yml)
— inside the official `ghcr.io/homebrew/brew` container. Outdated casks get an automatic
version + `sha256` bump PR. Users just run:

```sh
brew update && brew upgrade
```

## Adding a cask

1. Create `Casks/<first-letter>/<token>.rb` (homebrew-cask layout, token named after the
   upstream package).
2. Point `url` at the official upstream artifact; take `sha256` from the vendor's
   published checksums where available (apt `Packages` indexes carry them for free).
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
