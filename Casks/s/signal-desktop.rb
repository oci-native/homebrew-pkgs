cask "signal-desktop" do
  version "8.26.0"
  sha256 "5265d3e3090a9785393c7547f8d720658d04ee717efb5810e01de2221b032b3d"

  url "https://updates.signal.org/desktop/apt/pool/s/signal-desktop/signal-desktop_#{version}_amd64.deb"
  name "Signal"
  desc "Instant messaging application focusing on security"
  homepage "https://signal.org/"

  livecheck do
    url "https://updates.signal.org/desktop/apt/dists/xenial/main/binary-amd64/Packages"
    regex(/signal-desktop_(\d+(?:\.\d+)+)_amd64\.deb/i)
  end

  depends_on arch: :x86_64

  binary "opt/Signal/signal-desktop"
  artifact "usr/share/applications/signal-desktop.desktop",
           target: "#{Dir.home}/.local/share/applications/signal-desktop.desktop"
  artifact "usr/share/icons/hicolor/512x512/apps/signal-desktop.png",
           target: "#{Dir.home}/.local/share/icons/hicolor/512x512/apps/signal-desktop.png"

  preflight_steps do
    run "/usr/bin/bsdtar", args: ["-xf", "signal-desktop_#{version}_amd64.deb"], chdir: "."
    run "/usr/bin/bsdtar", args: ["-xf", "data.tar.xz"], chdir: "."
    inreplace "usr/share/applications/signal-desktop.desktop",
              "Exec=/opt/Signal/signal-desktop",
              "Exec={{HOMEBREW_PREFIX}}/bin/signal-desktop"
  end

  zap trash: "~/.config/Signal"
end
