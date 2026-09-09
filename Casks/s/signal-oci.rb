cask "signal-oci" do
  version "8.26.0"
  sha256 "5265d3e3090a9785393c7547f8d720658d04ee717efb5810e01de2221b032b3d"

  # The brew-verified .deb stays in the Caskroom; the launcher bakes it
  # into a debian-based image on first run.
  url "https://updates.signal.org/desktop/apt/pool/s/signal-desktop/signal-desktop_#{version}_amd64.deb"
  name "Signal (OCI)"
  desc "Signal messenger running inside a rootless container"
  homepage "https://signal.org/"

  livecheck do
    url "https://updates.signal.org/desktop/apt/dists/xenial/main/binary-amd64/Packages"
    regex(/signal-desktop_(\d+(?:\.\d+)+)_amd64\.deb/i)
  end

  depends_on arch: :x86_64

  binary "oci/bin/signal-oci"
  artifact "oci/share/signal-oci.desktop",
           target: "#{Dir.home}/.local/share/applications/signal-oci.desktop"
  artifact "usr/share/icons/hicolor/512x512/apps/signal-desktop.png",
           target: "#{Dir.home}/.local/share/icons/hicolor/512x512/apps/signal-oci.png"

  preflight_steps do
    run "/bin/sh",
        args:         ["-c",
                       "t='{{HOMEBREW_PREFIX}}/Homebrew/Library/Taps/oci-native/homebrew-pkgs/containers'; " \
                       "echo '==> containers/signal-oci/Containerfile'; " \
                       "cat \"$t/signal-oci/Containerfile\""],
        print_stdout: true
    run "/usr/bin/bsdtar", args: ["-xf", "signal-desktop_#{version}_amd64.deb", "data.tar.xz"], chdir: "."
    run "/usr/bin/bsdtar",
        args:  ["-xf", "data.tar.xz", "./usr/share/icons/hicolor/512x512/apps/signal-desktop.png"],
        chdir: "."
    mkdir_p "oci/bin"
    mkdir_p "oci/share"
    write_file "oci/bin/signal-oci", <<~SCRIPT
      #!/bin/sh
      # Launcher for Signal running from a locally built OCI image. Builds
      # the image from the tap's Containerfile plus the Caskroom .deb on
      # first run, or pulls from OCI_NATIVE_REGISTRY when set.
      set -eu

      APP="signal-oci"
      VERSION="{{version}}"
      STATE="${XDG_DATA_HOME:-$HOME/.local/share}/oci-apps/$APP"

      if command -v podman >/dev/null 2>&1; then
        ENGINE=podman
      elif command -v docker >/dev/null 2>&1; then
        ENGINE=docker
      else
        echo "$APP: need podman or docker on PATH" >&2
        exit 1
      fi

      if [ -n "${OCI_NATIVE_REGISTRY:-}" ]; then
        IMAGE="$OCI_NATIVE_REGISTRY/$APP:$VERSION"
        if ! "$ENGINE" image inspect "$IMAGE" >/dev/null 2>&1; then
          echo "$APP: pulling $IMAGE" >&2
          "$ENGINE" pull "$IMAGE"
        fi
      else
        IMAGE="localhost/oci-native/$APP:$VERSION"
        if ! "$ENGINE" image inspect "$IMAGE" >/dev/null 2>&1; then
          TAP_DIR=$(brew --repository oci-native/pkgs 2>/dev/null || true)
          CONTEXT="$TAP_DIR/containers/$APP"
          DEB="{{HOMEBREW_PREFIX}}/Caskroom/$APP/$VERSION/signal-desktop_${VERSION}_amd64.deb"
          if [ ! -f "$CONTEXT/Containerfile" ]; then
            echo "$APP: no Containerfile at $CONTEXT (is the tap installed?)" >&2
            exit 1
          fi
          if [ ! -f "$DEB" ]; then
            echo "$APP: missing $DEB (reinstall the cask?)" >&2
            exit 1
          fi
          BUILD_DIR=$(mktemp -d)
          trap 'rm -rf "$BUILD_DIR"' EXIT
          cp "$CONTEXT/Containerfile" "$BUILD_DIR/"
          cp "$DEB" "$BUILD_DIR/cask.deb"
          echo "$APP: building $IMAGE" >&2
          "$ENGINE" build -t "$IMAGE" "$BUILD_DIR"
        fi
      fi

      mkdir -p "$STATE/.config" "$STATE/.cache"

      set -- "$IMAGE" "$@"
      set -- --security-opt label=disable --shm-size=1g -e HOME=/data -v "$STATE:/data" "$@"
      if [ "$ENGINE" = podman ]; then
        # keep-groups carries the host's render/video group membership
        # into the container so /dev/dri render nodes stay accessible
        set -- --userns=keep-id --group-add keep-groups "$@"
      fi
      if [ -e /dev/dri ]; then
        set -- --device /dev/dri "$@"
      fi
      if [ -n "${WAYLAND_DISPLAY:-}" ] && [ -S "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/$WAYLAND_DISPLAY" ]; then
        RUNTIME="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
        set -- -e "WAYLAND_DISPLAY=$WAYLAND_DISPLAY" -e XDG_RUNTIME_DIR=/run/xdg -v "$RUNTIME/$WAYLAND_DISPLAY:/run/xdg/$WAYLAND_DISPLAY" "$@"
      fi
      if [ -n "${DISPLAY:-}" ] && [ -d /tmp/.X11-unix ]; then
        set -- -e "DISPLAY=$DISPLAY" -v /tmp/.X11-unix:/tmp/.X11-unix "$@"
        if [ -n "${XAUTHORITY:-}" ] && [ -f "$XAUTHORITY" ]; then
          set -- -e XAUTHORITY=/data/.Xauthority -v "$XAUTHORITY:/data/.Xauthority:ro" "$@"
        fi
      fi

      exec "$ENGINE" run --rm --name "oci-$APP-$$" "$@"
    SCRIPT
    set_permissions "oci/bin/signal-oci", "0755"
    write_file "oci/share/signal-oci.desktop", <<~DESKTOP
      [Desktop Entry]
      Name=Signal (OCI)
      Comment=Private messaging, containerized
      Exec={{HOMEBREW_PREFIX}}/bin/signal-oci %U
      Terminal=false
      Type=Application
      Icon=signal-oci
      StartupWMClass=signal
      MimeType=x-scheme-handler/sgnl;x-scheme-handler/signalcaptcha;
      Categories=Network;InstantMessaging;Chat;
    DESKTOP
  end

  zap trash: "~/.local/share/oci-apps/signal-oci"

  caveats <<~EOS
    Runs inside a container via podman (or docker). On first launch the
    image is built locally from the tap's Containerfile using the .deb
    this cask downloaded and verified; set OCI_NATIVE_REGISTRY to pull a
    prebuilt image from your own registry instead. App data lives in
    ~/.local/share/oci-apps/signal-oci.

    No dbus or audio is mounted yet, so desktop notifications and calls
    do not work in this variant.

    Uninstalling the cask leaves the image behind (brew's sandbox cannot
    reach the container storage). Remove it with:
      podman rmi localhost/oci-native/signal-oci:#{version}
  EOS
end
