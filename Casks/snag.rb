cask "snag" do
  version "1.0.0"
  sha256 :no_check

  url "https://github.com/sants2001/snag.git",
      using:    :git,
      branch:   "main"
  name "Snag"
  desc "Find any file on your Mac, instantly"
  homepage "https://github.com/sants2001/snag"

  depends_on macos: ">= :sequoia"

  # Built on the user's machine rather than downloaded.
  #
  # Snag has no Apple Developer ID, so a downloaded binary would be quarantined and refused by
  # Gatekeeper with a message that reads like corruption. Building locally sidesteps that
  # entirely: the resulting app is ad-hoc signed by the machine that will run it. It also means
  # nobody has to trust a binary from a stranger to run something that asks for Full Disk Access.
  #
  # The cost is honest: Xcode is required, and the first install takes a few minutes.
  preflight do
    unless File.directory?("/Applications/Xcode.app")
      raise Cask::CaskError, "Snag builds from source and needs Xcode. Install it from the App Store, then run `sudo xcode-select -s /Applications/Xcode.app`."
    end

    system_command "/usr/bin/xcodebuild",
                   args: [
                     "-project", "#{staged_path}/Snag.xcodeproj",
                     "-scheme", "Snag",
                     "-configuration", "Release",
                     "-destination", "platform=macOS",
                     "-derivedDataPath", "#{staged_path}/build",
                     "build",
                   ],
                   print_stderr: false

    built = Dir["#{staged_path}/build/Build/Products/Release/Snag.app"].first
    raise Cask::CaskError, "Build produced no Snag.app" if built.nil?

    # Re-sign inside-out. Sparkle ships pre-signed with its own Team ID and dyld refuses to load
    # it into an ad-hoc-signed process until the whole bundle carries one identity.
    system_command "#{staged_path}/sign-local.sh", args: [built], print_stderr: false
  end

  app "build/Build/Products/Release/Snag.app"

  caveats <<~EOS
    Snag needs Full Disk Access to index files outside your Home folder.
    Add it in System Settings > Privacy & Security > Full Disk Access.

    Summon the window with Right Command + /. There is no Dock or menu bar icon,
    so the hotkey is the only way in. Rebind it in Settings if another app has
    claimed that combination.

    Snag stores an index of every file NAME and PATH on your disk in
    ~/Library/Caches/com.santino.Snag (around 450 MB). It never reads file
    contents, and nothing leaves your machine. See SECURITY.md.
  EOS

  uninstall quit: "com.santino.Snag"

  zap trash: [
    "~/Library/Caches/com.santino.Snag",
    "~/Library/Preferences/com.santino.Snag.plist",
  ]
end
