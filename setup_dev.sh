#!/usr/bin/env bash
#
# setup_dev.sh - Development setup script for makecmd
#
# This script sets up the development environment for testing

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Setting up makecmd development environment..."

# Make scripts executable
chmod +x "$SCRIPT_DIR/makecmd"
chmod +x "$SCRIPT_DIR/install.sh"
chmod +x "$SCRIPT_DIR/run_tests.sh"
chmod +x "$SCRIPT_DIR/tests/security/test_injection.sh"
chmod +x "$SCRIPT_DIR/tests/integration/test_basic.sh"

# Create test symlink
ln -sf "$SCRIPT_DIR/makecmd" "$SCRIPT_DIR/mkcmd"

echo "✓ Scripts made executable"

# Run security tests
echo
echo "Running security tests..."
if "$SCRIPT_DIR/tests/security/test_injection.sh"; then
    echo "✓ Security tests passed"
else
    echo "✗ Security tests failed"
fi

echo
echo "Development setup complete!"
echo
echo "To test makecmd locally:"
echo "  ./makecmd --help"
echo "  ./makecmd --version"
echo
echo "To run all tests:"
echo "  ./run_tests.sh"
echo
echo "To install system-wide:"
echo "  ./install.sh"