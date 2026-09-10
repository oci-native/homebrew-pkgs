# OCI casks: apps delivered as container images

Most casks in this tap install an upstream `.deb` or AppImage. OCI casks work
differently: the app is defined by a Containerfile in this repo, and the cask installs a
small launcher that builds the image locally on first run and runs it with podman or
docker. To the desktop it looks like any other installed app. There is a `.desktop`
entry, an icon, and a binary on `PATH`. Underneath, the app runs in a rootless container
with only the sockets it needs.

Images come registry-first: the launcher pulls
`8gcr.container-registry.dev/oci-native/<app>:<version>` (published by CI on merge to
main). Each launcher also carries a `DIGEST=` line. When the publish workflow pushes
an image it signs it with cosign, verifies the signature, and rewrites that line with
the signed digest (the version stays as a trailing comment, the same style as
SHA-pinned GitHub Actions). A pinned launcher pulls `<app>@sha256:...` instead of the
tag, so the bytes that run are exactly the bytes that were signed. The registry is
still not a hard requirement, though. `brew tap` clones this repo, so every user
already has the Containerfile, and when the pull fails (offline, or the tag is not
published) the launcher builds the same image locally. Set `OCI_NATIVE_REGISTRY` to
pull from another registry, or `OCI_NATIVE_BUILD=1` to skip the pull and always
build.

Three casks are built this way. `galculator` is the minimal example: the Containerfile
installs the app from alpine packages. `signal-oci` is the real-world shape: a
debian-based image where the launcher bakes in the exact `.deb` the cask downloaded and
checksummed, so brew's `sha256` covers the binary that ends up in the image. `zoom-oci`
follows the same deb pattern and exercises every host access the launchers support:
GPU, speaker, microphone, and camera in one app. Read the casks alongside this
document.

## Why containers

Some apps have no Linux binary release, or their binaries assume one distro's libraries.
An image built from a known base solves both: the build is reproducible from the
`Containerfile` in this repo, the runtime dependencies travel with the app, and the host
stays clean. Rootless podman means no daemon and no root.

## The pieces

Each OCI app has three parts, and they agree on one version string:

1. `containers/<app>/Containerfile` builds the image; `ENTRYPOINT` is the app binary.
   A Containerfile that starts with `COPY cask.deb` receives the cask's own artifact:
   on clients the launcher copies the sha256-verified `.deb` from the Caskroom, and in
   CI (`task build:<app>`) gets the same file via `brew fetch --cask`. One download path,
   verified in both places.
2. `Casks/<letter>/<app>.rb` is the cask. Its `version` is the image tag. The cask
   writes a launcher script and a `.desktop` entry via `preflight_steps`; nothing is
   downloaded at install time except the small version-anchor artifact (see below).
3. The Taskfile's `build:<app>`/`push:<app>` tasks (and the publish workflow) can seed a
   registry for `OCI_NATIVE_REGISTRY` users. The default registry is
   `8gcr.container-registry.dev/oci-native`; override it with the `REGISTRY` env
   var locally or the repository variable in CI. The task reads the image tag from the
   cask, so image and cask cannot drift apart.

The image is built lazily, on first launch, by the launcher, from the Containerfile in
the local tap clone (found via `brew --repository oci-native/pkgs`). Install stays
instant. `brew uninstall` removes the launcher and desktop entry but leaves the image:
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
- builds `localhost/oci-native/<app>:<version>` from the tap's Containerfile if the
  image is missing, or pulls from `$OCI_NATIVE_REGISTRY` when that is set
- creates `~/.local/share/oci-apps/<app>` and mounts it as the container's `HOME`, so
  settings and caches persist across runs
- mounts the Wayland socket when `WAYLAND_DISPLAY` is set, and falls back to X11
  (`/tmp/.X11-unix` plus `XAUTHORITY`) when `DISPLAY` is set
- passes `/dev/dri` for GPU rendering when it exists, with `--group-add keep-groups`
  under podman so the host's render group membership still applies inside
- mounts the PulseAudio socket (`$XDG_RUNTIME_DIR/pulse/native`) with `PULSE_SERVER`
  set, when the host has one (signal-oci)
- mounts the PipeWire core socket (`$XDG_RUNTIME_DIR/pipewire-0`) for capture: the
  pulse socket covers playback and pulse-API recording, while apps that talk PipeWire
  directly (Chromium/WebRTC mic input) need the core socket (signal-oci)
- passes every `/dev/video*` device for camera access (signal-oci); `keep-groups` from
  the GPU change carries the host's video group membership
- uses `--userns=keep-id` under podman so file ownership in the state dir matches the
  host user

The container gets `--security-opt label=disable` so the socket mounts work on
SELinux hosts. It does not get the host home directory or the host's network
namespace. The dbus session socket is mounted (with `DBUS_SESSION_BUS_ADDRESS`
set), so desktop notifications reach the host; note that dbus EXTERNAL auth only
works because `--userns=keep-id` keeps the in-container uid equal to the socket
peer credential.

Host fonts are mounted read-only (`/usr/share/fonts`, `~/.local/share/fonts`,
`~/.fonts`) at paths the container's fontconfig scans, so non-latin scripts,
emoji, and user-installed fonts render without baking fonts into images. Images
keep DejaVu as the offline fallback; alpine-based images need a fontconfig
conf.d drop-in for `/usr/local/share/fonts` (see `containers/galculator`).
Launchers also set a stable `--hostname` so apps that record a hostname in
their profile locks (Chromium and friends) can recognise a stale lock after an
unclean exit.

## Adding an OCI app

1. Write `containers/<app>/Containerfile`. Test it locally:
   `task build:<app>` builds without pushing.
2. Run it by hand with the socket mounts from the launcher above and check the window
   appears.
3. Copy `Casks/g/galculator.rb` as a template. Change the token, the image name, the
   upstream `url` and `sha256`, and the `.desktop` fields. Pick an `Icon=` name that
   exists in common icon themes, or extend the cask to extract one from the image.
4. Verify: `brew style`, `brew audit --strict --online`, `brew install --cask`, launch,
   `brew uninstall --cask`.

## Current limits

- Casks declare `depends_on arch: :x86_64`; local builds would work on arm64 hosts
  whenever the base image and packages exist for it, so this can loosen per app once
  tested.
- A local build follows the Containerfile at whatever state the tap clone is in; the
  base image tag is pinned there, but package versions inside resolve at build time.
- Old image tags pile up across upgrades; the caveats show the `rmi` cleanup.
- signal-oci mounts the PulseAudio and PipeWire sockets and passes `/dev/video*`
  devices, so playback, microphone, camera, and desktop notifications all work.
- Electron apps run with --no-sandbox inside the container, since Chromium's sandbox
  cannot nest inside a rootless user namespace. The container is the sandbox.
- Each cask embeds its own launcher script. If the count grows, the shared logic should
  move to a small `oci-run` formula the casks depend on.
