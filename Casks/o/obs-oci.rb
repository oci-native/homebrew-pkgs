cask "obs-oci" do
  version "32.2.2-1"
  sha256 "160a66705327d25c617965bc2abbd92101443072a186ab682ee3f39d6c49746b"

  # The brew-verified .deb stays in the Caskroom; the launcher bakes it
  # into a debian-based image on first run.
  url "https://archive.archlinux.org/packages/o/obs-studio/obs-studio-#{version}-x86_64.pkg.tar.zst"
  name "OBS Studio (OCI)"
  desc "Screen and camera recorder running inside a rootless container"
  homepage "https://obsproject.com/"

  livecheck do
    url "https://archlinux.org/packages/extra/x86_64/obs-studio/json/"
    strategy :json do |json|
      "#{json["pkgver"]}-#{json["pkgrel"]}" if json["pkgver"]
    end
  end

  depends_on arch: :x86_64
  container type: :naked

  binary "oci/bin/obs-oci"
  artifact "oci/share/obs-oci.desktop",
           target: "#{Dir.home}/.local/share/applications/obs-oci.desktop"
  artifact "usr/share/icons/hicolor/256x256/apps/com.obsproject.Studio.png",
           target: "#{Dir.home}/.local/share/icons/hicolor/256x256/apps/obs-oci.png"

  preflight_steps do
    run "/bin/sh",
        args:         ["-c",
                       "t='{{HOMEBREW_PREFIX}}/Homebrew/Library/Taps/oci-native/homebrew-pkgs/containers'; " \
                       "echo '==> containers/obs-oci/Containerfile'; " \
                       "cat \"$t/obs-oci/Containerfile\""],
        print_stdout: true
    run "/usr/bin/bsdtar",
        args:  ["-xf", "obs-studio-#{version}-x86_64.pkg.tar.zst",
                "usr/share/icons/hicolor/256x256/apps/com.obsproject.Studio.png"],
        chdir: "."
    mkdir_p "oci/bin"
    mkdir_p "oci/share"
    write_file "oci/bin/obs-oci", <<~SCRIPT
      #!/bin/sh
      # Launcher for Signal running from a locally built OCI image. Builds
      # the image from the tap's Containerfile plus the Caskroom .deb on
      # first run, or pulls from OCI_NATIVE_REGISTRY when set.
      set -eu

      APP="obs-oci"
      VERSION="{{version}}"
      # OCI tags forbid '+' (debian revisions like 30.2.3+dfsg-3)
      TAG=$(printf '%s' "$VERSION" | tr '+' '-')
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
        IMAGE="$OCI_NATIVE_REGISTRY/$APP:$TAG"
        if ! "$ENGINE" image inspect "$IMAGE" >/dev/null 2>&1; then
          echo "$APP: pulling $IMAGE" >&2
          "$ENGINE" pull "$IMAGE"
        fi
      else
        IMAGE="localhost/oci-native/$APP:$TAG"
        if ! "$ENGINE" image inspect "$IMAGE" >/dev/null 2>&1; then
          TAP_DIR=$(brew --repository oci-native/pkgs 2>/dev/null || true)
          CONTEXT="$TAP_DIR/containers/$APP"
          PKG="{{HOMEBREW_PREFIX}}/Caskroom/$APP/$VERSION/obs-studio-${VERSION}-x86_64.pkg.tar.zst"
          if [ ! -f "$CONTEXT/Containerfile" ]; then
            echo "$APP: no Containerfile at $CONTEXT (is the tap installed?)" >&2
            exit 1
          fi
          if [ ! -f "$PKG" ]; then
            echo "$APP: missing $PKG (reinstall the cask?)" >&2
            exit 1
          fi
          BUILD_DIR=$(mktemp -d)
          trap 'rm -rf "$BUILD_DIR"' EXIT
          cp "$CONTEXT/Containerfile" "$BUILD_DIR/"
          cp "$PKG" "$BUILD_DIR/cask.pkg"
          echo "$APP: building $IMAGE" >&2
          "$ENGINE" build --build-arg "APP_VERSION=$VERSION" -t "$IMAGE" "$BUILD_DIR"
        fi
      fi

      mkdir -p "$STATE/.config" "$STATE/.cache"

      set -- "$IMAGE" "$@"
      # Stable hostname keeps per-run identity consistent for app locks.
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
    set_permissions "oci/bin/obs-oci", "0755"
    write_file "oci/share/obs-oci.desktop", <<~DESKTOP
      [Desktop Entry]
      Name=OBS Studio (OCI)
      Comment=Screen and camera recording, containerized
      Exec={{HOMEBREW_PREFIX}}/bin/obs-oci
      Terminal=false
      Type=Application
      Icon=obs-oci
      StartupWMClass=com.obsproject.Studio
      Categories=AudioVideo;Recorder;
    DESKTOP
  end

  zap trash: "~/.local/share/oci-apps/obs-oci"

  caveats <<~EOS
    Runs inside a container via podman (or docker). On first launch the
    image is built locally from the tap's Containerfile using the arch
    package this cask downloaded and verified; set OCI_NATIVE_REGISTRY to pull a
    prebuilt image from your own registry instead. App data lives in
    ~/.local/share/oci-apps/obs-oci.

    Uninstalling the cask leaves the image behind (brew's sandbox cannot
    reach the container storage). Remove it with:
      podman rmi localhost/oci-native/obs-oci:#{version.to_s.tr("+", "-")}
  EOS
end
