class Makecmd < Formula
  desc "Convert natural language to shell commands using Claude Code"
  homepage "https://github.com/Cosmic-Skye/makecmd"
  url "https://github.com/Cosmic-Skye/makecmd/archive/v1.0.0.tar.gz"
  sha256 "a1b2c3d4e5f6789012345678901234567890abcdef1234567890abcdef123456"
  license "MIT"
  
  depends_on "claude-code" => :runtime
  
  def install
    # Install main script
    bin.install "makecmd"
    
    # Create symlink for mkcmd
    bin.install_symlink "makecmd" => "mkcmd"
    
    # Install library files
    lib.install Dir["lib/*.sh"]
    
    # Update library paths in main script
    inreplace bin/"makecmd" do |s|
      s.gsub! /source "\$\{SCRIPT_DIR\}\/lib\//, "source \"#{lib}/makecmd/"
    end
    
    # Install man page
    man1.install "docs/makecmd.1"
    
    # Install bash completion
    bash_completion.install "completions/makecmd.bash"
    
    # Install zsh completion
    zsh_completion.install "completions/_makecmd"
  end
  
  def post_install
    # Create config directory
    (var/"makecmd").mkpath
    
    # Create default config if it doesn't exist
    config_file = etc/"makecmdrc"
    unless config_file.exist?
      config_file.write <<~EOS
        # makecmd configuration file
        # See makecmd --help for details
        
        output_mode = auto
        cache_ttl = 3600
        safe_mode = false
        debug = false
        timeout = 30
        max_input_length = 500
        color_output = true
      EOS
    end
  end
  
  def caveats
    <<~EOS
      makecmd has been installed! 
      
      Requirements:
        - Claude Code must be installed and authenticated
        - Install from: https://claude.ai/code
      
      Quick start:
        makecmd "list all python files"
        mkcmd "show disk usage"
      
      Configuration:
        System config: #{etc}/makecmdrc
        User config: ~/.makecmdrc
      
      For security information:
        makecmd --help
    EOS
  end
  
  test do
    # Test help command
    assert_match "Convert natural language to shell commands", shell_output("#{bin}/makecmd --help")
    
    # Test version command
    assert_match "makecmd version", shell_output("#{bin}/makecmd --version")
    
    # Test mkcmd symlink
    assert_match "Convert natural language to shell commands", shell_output("#{bin}/mkcmd --help")
  end
end