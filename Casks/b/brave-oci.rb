cask "brave-oci" do
  version "1.94.121"
  sha256 "21d7ac36b64a408dc598bb6ec3db84b07b2cbca854d26b28055a2fb5b94a2e77"

  # The brew-verified .deb stays in the Caskroom; the launcher bakes it
  # into a debian-based image on first run.
  url "https://brave-browser-apt-release.s3.brave.com/pool/main/b/brave-browser/brave-browser_#{version}_amd64.deb"
  name "Brave (OCI)"
  desc "Web browser running inside a rootless container"
  homepage "https://brave.com/"

  livecheck do
    url "https://brave-browser-apt-release.s3.brave.com/dists/stable/main/binary-amd64/Packages"
    regex(/brave-browser_(\d+(?:\.\d+)+)_amd64\.deb/i)
  end

  depends_on arch: :x86_64

  binary "oci/bin/brave-oci"
  artifact "oci/share/brave-oci.desktop",
           target: "#{Dir.home}/.local/share/applications/brave-oci.desktop"
  artifact "opt/brave.com/brave/product_logo_256.png",
           target: "#{Dir.home}/.local/share/icons/hicolor/256x256/apps/brave-oci.png"

  preflight_steps do
    run "/bin/sh",
        args:         ["-c",
                       "t='{{HOMEBREW_PREFIX}}/Homebrew/Library/Taps/oci-native/homebrew-pkgs/containers'; " \
                       "echo '==> containers/brave-oci/Containerfile'; " \
                       "cat \"$t/brave-oci/Containerfile\""],
        print_stdout: true
    run "/usr/bin/bsdtar", args: ["-xf", "brave-browser_#{version}_amd64.deb", "data.tar.xz"], chdir: "."
    run "/usr/bin/bsdtar", args: ["-xf", "data.tar.xz", "./opt/brave.com/brave/product_logo_256.png"], chdir: "."
    mkdir_p "oci/bin"
    mkdir_p "oci/share"
    write_file "oci/bin/brave-oci", <<~SCRIPT
      #!/bin/sh
      # Launcher for Brave running from an OCI image: pulls the published
      # image first, or builds it from the tap's Containerfile plus the
      # Caskroom .deb when the pull fails.
      set -eu

      APP="brave-oci"
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

      # Registry-first: pull the published image, fall back to a local
      # build when the pull fails (offline, or the registry lacks the
      # tag). OCI_NATIVE_BUILD=1 skips the pull entirely.
      REGISTRY="${OCI_NATIVE_REGISTRY:-8gcr.container-registry.dev/oci-native}"
      IMAGE="$REGISTRY/$APP:$VERSION"
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
          DEB="{{HOMEBREW_PREFIX}}/Caskroom/$APP/$VERSION/brave-browser_${VERSION}_amd64.deb"
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
          "$ENGINE" build --build-arg "APP_VERSION=$VERSION" -t "$IMAGE" "$BUILD_DIR"
        fi
      fi

      mkdir -p "$STATE/.config" "$STATE/.cache"

      set -- "$IMAGE" "$@"
      # Stable hostname lets Chromium recognise its own stale profile
      # lock after an unclean exit instead of refusing to start.
      set -- --security-opt label=disable --shm-size=1g --hostname "$APP" -e HOME=/data -v "$STATE:/data" "$@"
      # Host fonts, read-only: the image ships only DejaVu; everything
      # else (indic scripts, emoji, user fonts) comes from the host.
      # The container's fontconfig scans these paths by default.
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
      for dev in /dev/video*; do
        [ -e "$dev" ] && set -- --device "$dev" "$@"
      done
      if [ -S "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/pulse/native" ]; then
        RUNTIME="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
        set -- -e PULSE_SERVER=unix:/run/xdg/pulse/native -v "$RUNTIME/pulse/native:/run/xdg/pulse/native" "$@"
      fi
      if [ -S "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/pipewire-0" ]; then
        RUNTIME="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
        set -- -v "$RUNTIME/pipewire-0:/run/xdg/pipewire-0" "$@"
      fi
      if [ -S "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/bus" ]; then
        RUNTIME="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
        set -- -e DBUS_SESSION_BUS_ADDRESS=unix:path=/run/xdg/bus -v "$RUNTIME/bus:/run/xdg/bus" "$@"
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
    set_permissions "oci/bin/brave-oci", "0755"
    write_file "oci/share/brave-oci.desktop", <<~DESKTOP
      [Desktop Entry]
      Name=Brave (OCI)
      Comment=Web browsing, containerized
      Exec={{HOMEBREW_PREFIX}}/bin/brave-oci %U
      Terminal=false
      Type=Application
      Icon=brave-oci
      StartupWMClass=brave-browser
      MimeType=text/html;x-scheme-handler/http;x-scheme-handler/https;
      Categories=Network;WebBrowser;
    DESKTOP
  end

  zap trash: "~/.local/share/oci-apps/brave-oci"

  caveats <<~EOS
    Runs inside a container via podman (or docker). On first launch the
    image is pulled from 8gcr.container-registry.dev/oci-native, falling
    back to a local build from the tap's Containerfile using the .deb
    this cask downloaded and verified. Set OCI_NATIVE_REGISTRY to use
    another registry, or OCI_NATIVE_BUILD=1 to always build locally. App
    data lives in ~/.local/share/oci-apps/brave-oci.

    Uninstalling the cask leaves the image behind (brew's sandbox cannot
    reach the container storage). Remove it with:
      podman rmi 8gcr.container-registry.dev/oci-native/brave-oci:#{version}
    (or localhost/oci-native/brave-oci:#{version} if it was built locally)
  EOS
end
