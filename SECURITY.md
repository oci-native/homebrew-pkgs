# Security

## Reporting a vulnerability

Use GitHub's private vulnerability reporting: the Security tab on this repository,
then "Report a vulnerability". Do not open a public issue for anything exploitable.

## What this tap guarantees

- Every cask artifact is downloaded from the official vendor URL and pinned by
  `sha256`. Homebrew verifies the checksum before anything is unpacked or built.
- Install-time steps run inside Homebrew's sandbox (Landlock on Linux) with network
  access denied unless a step declares it.
- OCI images are built locally from Containerfiles in this repo. The base image tag is
  pinned; the app payload is the same sha256-verified artifact the cask downloaded.
- Containers run rootless, without the host home directory or host network namespace.
  Only the display socket, GPU and video devices, audio sockets, the dbus session
  socket (for notifications), host font directories (read-only), and a per-app
  state directory are mounted.

## Known trade-offs

- Base images are pinned by tag, not digest, and packages inside an image resolve at
  build time. Two machines building on different days can get different package
  versions.
- Electron and Chromium apps run with `--no-sandbox` inside their container; the
  container boundary replaces the browser sandbox, which cannot nest inside a rootless
  user namespace.
- A locally built image is rebuilt on version bumps, not on base-image security
  updates. Remove the local image (`podman rmi`) to force a fresh build sooner.

## Scope

The tap's casks, Containerfiles, scripts, and workflows. Vulnerabilities in the
packaged applications themselves belong upstream with their vendors.
