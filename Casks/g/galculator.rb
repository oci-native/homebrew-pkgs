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
    mkdir_p "oci/bin"
    mkdir_p "oci/share"
    write_file "oci/bin/galculator", <<~SCRIPT
      #!/bin/sh
      # Launcher for the oci-native galculator image. Ensures the image is
      # present, then runs it with the host's display sockets and GPU.
      set -eu

      IMAGE="ghcr.io/oci-native/galculator:{{version}}"
      APP="galculator"
      STATE="${XDG_DATA_HOME:-$HOME/.local/share}/oci-apps/$APP"

      if command -v podman >/dev/null 2>&1; then
        ENGINE=podman
      elif command -v docker >/dev/null 2>&1; then
        ENGINE=docker
      else
        echo "galculator: need podman or docker on PATH" >&2
        exit 1
      fi

      if ! "$ENGINE" image inspect "$IMAGE" >/dev/null 2>&1; then
        echo "galculator: pulling $IMAGE" >&2
        "$ENGINE" pull "$IMAGE"
      fi

      mkdir -p "$STATE/.config" "$STATE/.cache"

      set -- "$IMAGE" "$@"
      set -- --security-opt label=disable -e HOME=/data -v "$STATE:/data" "$@"
      if [ "$ENGINE" = podman ]; then
        set -- --userns=keep-id "$@"
      fi
      if [ -e /dev/dri ]; then
        set -- --device /dev/dri "$@"
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
    Runs inside a container via podman (or docker). The image is pulled on
    first launch. App data lives in ~/.local/share/oci-apps/galculator.

    Uninstalling the cask leaves the image behind (brew's sandbox cannot
    reach the container storage). Remove it with:
      podman rmi ghcr.io/oci-native/galculator:#{version}
  EOS
end
