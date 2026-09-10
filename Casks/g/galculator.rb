cask "galculator" do
  version "2.1.4"
  sha256 "dcbdb48ddf8a3f68b9aa5902f880f174fd269de2b7410988148d05871012e142"

  # The url pins the upstream source release for version and checksum
  # bookkeeping; the runnable artifact is the OCI image below.
  url "https://github.com/galculator/galculator/archive/refs/tags/v#{version}.tar.gz"
  name "Galculator"
  desc "GTK scientific calculator, run from an OCI image"
  homepage "https://github.com/galculator/galculator"

  livecheck do
    url "https://github.com/galculator/galculator.git"
    regex(/^v?(\d+(?:\.\d+)+)$/i)
    strategy :git
  end

  depends_on arch: :x86_64

  binary "oci/bin/galculator"
  artifact "oci/share/galculator-oci.desktop",
           target: "#{Dir.home}/.local/share/applications/galculator-oci.desktop"

  preflight_steps do
    run "/bin/sh",
        args:         ["-c",
                       "t='{{HOMEBREW_PREFIX}}/Homebrew/Library/Taps/oci-native/homebrew-pkgs/containers'; " \
                       "echo '==> containers/galculator/Containerfile'; " \
                       "cat \"$t/galculator/Containerfile\""],
        print_stdout: true
    mkdir_p "oci/bin"
    mkdir_p "oci/share"
    write_file "oci/bin/galculator", <<~SCRIPT
      #!/bin/sh
      # Launcher for the oci-native galculator app: pulls the published
      # image first, or builds it locally from the tap's Containerfile
      # when the pull fails.
      set -eu

      APP="galculator"
      VERSION="{{version}}"
      # Digest of the signed image; the publish workflow rewrites this
      # line after every push (version stays as the side comment).
      DIGEST="" # {{version}}
      STATE="${XDG_DATA_HOME:-$HOME/.local/share}/oci-apps/$APP"

      if command -v podman >/dev/null 2>&1; then
        ENGINE=podman
      elif command -v docker >/dev/null 2>&1; then
        ENGINE=docker
      else
        echo "$APP: need podman or docker on PATH" >&2
        exit 1
      fi

      # Registry-first: pull the published image, fall back to a local
      # build when the pull fails (offline, or the registry lacks the
      # tag). OCI_NATIVE_BUILD=1 skips the pull entirely.
      REGISTRY="${OCI_NATIVE_REGISTRY:-8gcr.container-registry.dev/oci-native}"
      if [ -n "$DIGEST" ]; then
        IMAGE="$REGISTRY/$APP@$DIGEST"
      else
        IMAGE="$REGISTRY/$APP:$VERSION"
      fi
      PULLED=""
      if ! "$ENGINE" image inspect "$IMAGE" >/dev/null 2>&1; then
        if [ -z "${OCI_NATIVE_BUILD:-}" ]; then
          echo "$APP: pulling $IMAGE" >&2
          if "$ENGINE" pull "$IMAGE"; then
            PULLED=1
          fi
        fi
      else
        PULLED=1
      fi
      if [ -z "$PULLED" ]; then
        IMAGE="localhost/oci-native/$APP:$VERSION"
        if ! "$ENGINE" image inspect "$IMAGE" >/dev/null 2>&1; then
          TAP_DIR=$(brew --repository oci-native/pkgs 2>/dev/null || true)
          CONTEXT="$TAP_DIR/containers/$APP"
          if [ ! -f "$CONTEXT/Containerfile" ]; then
            echo "$APP: no Containerfile at $CONTEXT (is the tap installed?)" >&2
            exit 1
          fi
          echo "$APP: building $IMAGE from $CONTEXT" >&2
          "$ENGINE" build -t "$IMAGE" "$CONTEXT"
        fi
      fi

      mkdir -p "$STATE/.config" "$STATE/.cache"

      set -- "$IMAGE" "$@"
      # Stable hostname keeps per-run identity consistent for app locks.
      set -- --security-opt label=disable --hostname "$APP" -e HOME=/data -v "$STATE:/data" "$@"
      # Host fonts, read-only: the image ships only DejaVu; everything
      # else (indic scripts, emoji, user fonts) comes from the host.
      # The image's fontconfig is taught these paths in the Containerfile.
      if [ -d /usr/share/fonts ]; then
        set -- -v /usr/share/fonts:/usr/local/share/fonts/host:ro "$@"
      fi
      if [ -d "$HOME/.local/share/fonts" ]; then
        set -- -v "$HOME/.local/share/fonts:/data/.local/share/fonts:ro" "$@"
      fi
      if [ -d "$HOME/.fonts" ]; then
        set -- -v "$HOME/.fonts:/data/.fonts:ro" "$@"
      fi
      if [ "$ENGINE" = podman ]; then
        # keep-groups carries the host's render/video group membership
        # into the container so /dev/dri render nodes stay accessible
        set -- --userns=keep-id --group-add keep-groups "$@"
      fi
      if [ -e /dev/dri ]; then
        set -- --device /dev/dri "$@"
      fi
      if [ -S "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/bus" ]; then
        RUNTIME="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
        set -- -e DBUS_SESSION_BUS_ADDRESS=unix:path=/run/xdg/bus -v "$RUNTIME/bus:/run/xdg/bus" "$@"
      fi
      if [ -n "${WAYLAND_DISPLAY:-}" ] && [ -S "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/$WAYLAND_DISPLAY" ]; then
        RUNTIME="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
        set -- -e "WAYLAND_DISPLAY=$WAYLAND_DISPLAY" -v "$RUNTIME/$WAYLAND_DISPLAY:/run/xdg/$WAYLAND_DISPLAY" "$@"
      fi
      if [ -n "${DISPLAY:-}" ] && [ -d /tmp/.X11-unix ]; then
        set -- -e "DISPLAY=$DISPLAY" -v /tmp/.X11-unix:/tmp/.X11-unix "$@"
        if [ -n "${XAUTHORITY:-}" ] && [ -f "$XAUTHORITY" ]; then
          set -- -e XAUTHORITY=/data/.Xauthority -v "$XAUTHORITY:/data/.Xauthority:ro" "$@"
        fi
      fi

      exec "$ENGINE" run --rm --name "oci-$APP-$$" "$@"
    SCRIPT
    set_permissions "oci/bin/galculator", "0755"
    write_file "oci/share/galculator-oci.desktop", <<~DESKTOP
      [Desktop Entry]
      Name=Galculator
      Comment=GTK scientific calculator (OCI)
      Exec={{HOMEBREW_PREFIX}}/bin/galculator
      Terminal=false
      Type=Application
      Icon=accessories-calculator
      Categories=Utility;Calculator;
    DESKTOP
  end

  zap trash: "~/.local/share/oci-apps/galculator"

  caveats <<~EOS
    Runs inside a container via podman (or docker). On first launch the
    image is pulled from 8gcr.container-registry.dev/oci-native, falling
    back to a local build from the tap's Containerfile. Set
    OCI_NATIVE_REGISTRY to use another registry, or OCI_NATIVE_BUILD=1
    to always build locally. App data lives in
    ~/.local/share/oci-apps/galculator.

    Uninstalling the cask leaves the image behind (brew's sandbox cannot
    reach the container storage). Remove it with:
      podman rmi 8gcr.container-registry.dev/oci-native/galculator:#{version}
    (or localhost/oci-native/galculator:#{version} if it was built locally)
  EOS
end
