cask "signal-desktop" do
  arch arm: "arm64", intel: "x64"

  version "8.26.0"
  sha256 arm:          "746090d935d5480966f15ac618f6d3917a094a3472e36e1605797f2734faf413",
         intel:        "02b54a241b571db0e4fbc4e5c23dbd67a96105e6f36bd866ce4c03e5c7aabc36",
         x86_64_linux: "5265d3e3090a9785393c7547f8d720658d04ee717efb5810e01de2221b032b3d"

  on_macos do
    url "https://updates.signal.org/desktop/signal-desktop-mac-#{arch}-#{version}.zip"

    auto_updates true
    depends_on macos: :monterey

    app "Signal.app"

    zap trash: [
      "~/Library/Application Support/Signal",
      "~/Library/Preferences/org.whispersystems.signal-desktop.helper.plist",
      "~/Library/Preferences/org.whispersystems.signal-desktop.plist",
      "~/Library/Saved Application State/org.whispersystems.signal-desktop.savedState",
    ]
  end
  on_linux do
    url "https://updates.signal.org/desktop/apt/pool/s/signal-desktop/signal-desktop_#{version}_amd64.deb"

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

  name "Signal"
  desc "Instant messaging application focusing on security"
  homepage "https://signal.org/"

  livecheck do
    url "https://updates.signal.org/desktop/apt/dists/xenial/main/binary-amd64/Packages"
    regex(/signal-desktop_(\d+(?:\.\d+)+)_amd64\.deb/i)
  end
end
