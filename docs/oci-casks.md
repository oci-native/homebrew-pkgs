# OCI casks: apps delivered as container images

Most casks in this tap install an upstream `.deb` or AppImage. OCI casks work
differently: the app ships as a container image under `ghcr.io/oci-native`, and the cask
installs a small launcher that runs it with podman or docker. To the desktop it looks
like any other installed app. There is a `.desktop` entry, an icon, and a binary on
`PATH`. Underneath, the app runs in a rootless container with only the sockets it needs.

`galculator` is the first cask built this way. Read `Casks/g/galculator.rb` alongside
this document.

## Why containers

Some apps have no Linux binary release, or their binaries assume one distro's libraries.
An image built from a known base solves both: the build is reproducible from the
`Containerfile` in this repo, the runtime dependencies travel with the app, and the host
stays clean. Rootless podman means no daemon and no root.

## The pieces

Each OCI app has three parts, and they agree on one version string:

1. `containers/<app>/Containerfile` builds the image. Alpine base, the app, fonts, an
   icon theme, and mesa for GPU rendering. `ENTRYPOINT` is the app binary.
2. `Casks/<letter>/<app>.rb` is the cask. Its `version` is the image tag. The cask
   writes a launcher script and a `.desktop` entry via `preflight_steps`; nothing is
   downloaded at install time except the small version-anchor artifact (see below).
3. `.github/workflows/publish-images.yml` builds and pushes
   `ghcr.io/oci-native/<app>:<version>` whenever a Containerfile changes on main, using
   `scripts/publish-image.sh`. The script reads the tag from the cask, so image and cask
   cannot drift apart.

The image is pulled lazily, on first launch, by the launcher. Install stays instant and
offline. `brew uninstall` removes the launcher and desktop entry but leaves the image:
brew runs uninstall steps in a sandbox that cannot reach the container storage, so the
cask's caveats print the `podman rmi` command instead of failing silently.

## The version anchor

A cask must have a `url` and `sha256`. For an OCI cask the runnable artifact is the
image, which brew cannot fetch, so the `url` points at the app's upstream source release
tarball instead. That gives the cask a real checksum, a `livecheck` target, and a version
that autobump can manage. When autobump opens a PR for a new upstream release, the
launcher's image tag moves with it (the tag is templated from `version`), and the publish
workflow builds the matching image once the Containerfile picks up the new version.

## What the launcher does

The generated script, linked into the brew prefix by the `binary` stanza:

- picks podman if present, docker otherwise
- pulls the image if it is missing locally
- creates `~/.local/share/oci-apps/<app>` and mounts it as the container's `HOME`, so
  settings and caches persist across runs
- mounts the Wayland socket when `WAYLAND_DISPLAY` is set, and falls back to X11
  (`/tmp/.X11-unix` plus `XAUTHORITY`) when `DISPLAY` is set
- passes `/dev/dri` for GPU rendering when it exists
- uses `--userns=keep-id` under podman so file ownership in the state dir matches the
  host user

The container gets `--security-opt label=disable` so the socket mounts work on
SELinux hosts. It does not get the session dbus, the host home directory, or the
network namespace of the host. Apps that need dbus (tray icons, notifications,
portals) will need those mounts added per app.

## Adding an OCI app

1. Write `containers/<app>/Containerfile`. Test it locally:
   `./scripts/publish-image.sh <app>` builds without pushing.
2. Run it by hand with the socket mounts from the launcher above and check the window
   appears.
3. Copy `Casks/g/galculator.rb` as a template. Change the token, the image name, the
   upstream `url` and `sha256`, and the `.desktop` fields. Pick an `Icon=` name that
   exists in common icon themes, or extend the cask to extract one from the image.
4. Verify: `brew style`, `brew audit --strict --online`, `brew install --cask`, launch,
   `brew uninstall --cask`.

## Current limits

- Images are amd64 only, matching the `depends_on arch: :x86_64` in the casks. arm64
  needs multi-arch builds in the publish workflow.
- The image tag is pinned but not the digest. Digest pinning would make the pull
  reproducible; it needs the publish workflow to write the digest back into the cask.
- Audio (pipewire socket) and dbus are not mounted. Fine for a calculator, needed for
  chat or media apps.
- Each cask embeds its own launcher script. If the count grows, the shared logic should
  move to a small `oci-run` formula the casks depend on.
