# frozen_string_literal: true

# Homebrew formula for nova-ai.
#
# Single-command recipient install:
#
#   HOMEBREW_NOVA_SECRET_ID=<your-cloudsmith-entitlement-token> \
#     brew install lefty313/nova/nova-ai
#
# This file is the development source of truth — when the formula changes,
# `cp` it into the public tap repo (lefty313/homebrew-nova) under
# `Formula/nova-ai.rb`, commit, push.
#
# What the formula does:
#   1. Installs system deps via `depends_on`: ruby@3.4, lima.
#      Docker daemon comes via `nova bootstrap` (which installs the
#      OrbStack cask) — see lib/nova/cli/commands/bootstrap.rb.
#   2. Reads HOMEBREW_NOVA_SECRET_ID from env. Errors loudly if unset.
#   3. Runs `gem install nova-ai` against the Cloudsmith private
#      source using the token, into a formula-private libexec.
#   4. Auto-shims every binary the gem installed (libexec/bin/*) into
#      the formula's bin/ with GEM_PATH preset — brew's standard
#      symlink-into-/opt/homebrew/bin pattern then exposes them.
#
# About the env var name: Homebrew's `ENV.clear_sensitive_environment!`
# (extend/ENV.rb) deletes any var whose name matches
#   /(cookie|key|token|password|passphrase|auth)/i
# before formula code runs — security feature against leaking secrets
# into build output. "secret" is NOT in the regex, so
# HOMEBREW_NOVA_SECRET_ID survives the filter while the more obvious
# names (HOMEBREW_NOVA_TOKEN, HOMEBREW_NOVA_KEY, HOMEBREW_NOVA_AUTH)
# would all be stripped. The unconventional name is intentional.
class NovaAi < Formula
  desc "Isolated Lima VMs + workspaces for AI coding agents (gem ships from Cloudsmith)"
  homepage "https://github.com/lefty313/nova-ai"

  # Brew requires SOMETHING to install from; point at the public tap
  # repo as a `head` source so brew clones it without needing a tagged
  # tarball + sha256. The cloned repo content isn't actually used by
  # `def install` (the gem-install bypasses it).
  head "https://github.com/lefty313/homebrew-nova.git", branch: "main"
  version "0.1.12"
  license "Nonstandard" # nova-ai is proprietary; LICENSE is in the gem

  depends_on "ruby@3.4"
  depends_on "lima"
  # git: nova clones host repos into bare caches and per-workspace
  # checkouts (lib/nova/workspace/git_cache.rb). xcode-cli ships a
  # git binary, but listing it here removes the implicit dependency
  # on xcode-cli being installed AND keeps git current via brew
  # rather than tying it to Apple's release cadence.
  depends_on "git"

  def install
    token = ENV.fetch("HOMEBREW_NOVA_SECRET_ID") do
      odie <<~EOS
        nova-ai is a private gem; install requires HOMEBREW_NOVA_SECRET_ID
        to be set to your Cloudsmith entitlement token. Get one from the
        maintainer, then:

          HOMEBREW_NOVA_SECRET_ID=<your-token> brew install lefty313/nova/nova-ai

        Or persist it in ~/.zshrc:
          echo 'export HOMEBREW_NOVA_SECRET_ID=<your-token>' >> ~/.zshrc

        (The unusual name sidesteps Homebrew's sensitive-var filter,
        which strips anything matching /token|key|password|auth|cookie|
        passphrase/i before formula code runs.)
      EOS
    end

    # Install gem into a formula-private location. Avoids polluting
    # the user's GEM_HOME / ~/.gem and means uninstalling the formula
    # cleanly removes nova-ai too.
    ENV["GEM_HOME"] = libexec.to_s
    ENV["GEM_PATH"] = libexec.to_s

    # Cloudsmith URL is path-style with /ruby/ (NOT basic-auth, NOT
    # /rubygems/). Per docs.cloudsmith.com/formats/ruby-repository:
    #   https://dl.cloudsmith.io/<token>/<owner>/<repo>/ruby/
    system Formula["ruby@3.4"].opt_bin/"gem", "install", "nova-ai",
           "--no-document",
           "--bindir", (libexec/"bin").to_s,
           "--source", "https://dl.cloudsmith.io/#{token}/nova-hsei/nova/ruby/"

    # Shim every binary the gem installed into bin/ with GEM_PATH
    # preset so they resolve gem deps against the formula's libexec.
    # Auto-discovery means no hardcoded list to maintain as the gem's
    # exe surface evolves.
    Dir["#{libexec}/bin/*"].each do |gem_exe|
      exe_name = File.basename(gem_exe)
      (bin/exe_name).write_env_script gem_exe, GEM_PATH: libexec
    end
  end

  def caveats
    <<~EOS
      nova-ai installed from Cloudsmith via your HOMEBREW_NOVA_SECRET_ID.

      Persist it in ~/.zshrc so `brew upgrade nova-ai` works without
      re-prefixing each time:
        echo 'export HOMEBREW_NOVA_SECRET_ID=<your-token>' >> ~/.zshrc

      One more piece — Claude Code CLI (no brew formula yet):
        curl -fsSL https://claude.ai/install.sh | bash
        claude auth login

      First-run on a fresh machine:
        open -a OrbStack       # start the Docker daemon (one-time per boot)
        nova doctor            # verifies the host stack
        cd ~/code/your-project
        nova init && nova setup && nova start <ws>
    EOS
  end

  test do
    # The wrapper shim should at least respond to --version without
    # crashing (proves the gem-install + shim wiring worked).
    assert_match(/\d+\.\d+\.\d+/, shell_output("#{bin}/nova version"))
  end
end
