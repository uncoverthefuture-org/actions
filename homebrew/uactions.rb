# UActions Homebrew Formula
# https://github.com/uncoverthefuture-org/actions
#
# Install:
#   brew install uncver/actions/uactions
#   OR  
#   brew tap uncver/actions && brew install uactions

class Uactions < Formula
  desc "Local container deployment with Podman and Traefik"
  homepage "https://github.com/uncoverthefuture-org/actions"
  license "MIT"
  version "1.4.0"

  depends_on "node" => ">=18"

  def install
    # Create bin directory
    (bin).mkpath

    # Create a wrapper script that uses npx to run @uncver/actions
    bin.write_script "uactions", <<~SHELL
      #!/bin/bash
      exec npx --yes @uncver/actions "$@"
    SHELL

    # Make executable
    chmod 0755, bin/"uactions"
  end

  def caveats
    <<~EOS
      UActions installed successfully!

      Requirements:
      - Node.js 18+: brew install node
      - Podman: brew install podman

      First time setup:
        uactions init --domain yourdomain.pc

      Usage:
        uactions deploy my-app    # Deploy an app
        uactions watch           # Auto-deploy on changes  
        uactions list           # List deployments
        uactions status         # Show system status

      For help: uactions --help
    EOS
  end

  test do
    assert_match "uactions", pipe_output("#{bin}/uactions --help 2>&1", "")
  end
end