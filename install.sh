#!/bin/bash
# GT Mesh — One-command plugin installer
# Usage: curl -fsSL https://raw.githubusercontent.com/Deepwork-AI/gt-mesh/main/install.sh | bash
#
# Or: git clone https://github.com/Deepwork-AI/gt-mesh.git && cd gt-mesh && bash install.sh

set -e

REPO="https://github.com/Deepwork-AI/gt-mesh.git"
INSTALL_DIR="${GT_ROOT:-.}/.gt-mesh"
SKILLS_DIR="${HOME}/.claude/skills"
MCP_CONFIG="${HOME}/.claude/mcp.json"

echo "========================================="
echo "  GT Mesh — Plugin Installer"
echo "  Collaborative coding for Gas Town"
echo "========================================="
echo ""

# Detect if we're inside a Gas Town
if [ -f "./mayor/town.json" ] || [ -d "./.beads" ] || command -v gt &>/dev/null; then
  echo "[ok] Gas Town detected"
  GT_ROOT="${GT_ROOT:-.}"
else
  echo "[warn] No Gas Town detected in current directory"
  echo "       Install will proceed, but gt mesh commands need a running GT"
  GT_ROOT="${GT_ROOT:-.}"
fi

# Step 1: Clone or update gt-mesh
echo ""
echo "[1/5] Installing gt-mesh plugin..."
if [ -d "$INSTALL_DIR" ]; then
  echo "       Updating existing installation..."
  cd "$INSTALL_DIR" && git pull --quiet origin dev 2>/dev/null || git pull --quiet origin main 2>/dev/null || true && cd - >/dev/null
else
  git clone --quiet "$REPO" "$INSTALL_DIR"
fi
echo "       Installed to $INSTALL_DIR"

# Step 2: Install skills
echo ""
echo "[2/5] Installing Claude Code skills..."
mkdir -p "$SKILLS_DIR"

# Copy mesh skill
if [ -d "$INSTALL_DIR/skills/gt-mesh" ]; then
  cp -r "$INSTALL_DIR/skills/gt-mesh" "$SKILLS_DIR/gt-mesh"
  echo "       gt-mesh skill installed"
fi

# Copy mesh-contributor skill
if [ -d "$INSTALL_DIR/skills/gt-mesh-contributor" ]; then
  cp -r "$INSTALL_DIR/skills/gt-mesh-contributor" "$SKILLS_DIR/gt-mesh-contributor"
  echo "       gt-mesh-contributor skill installed"
fi

# Copy mesh-setup skill (interactive wizard)
if [ -d "$INSTALL_DIR/skills/gt-mesh-setup" ]; then
  cp -r "$INSTALL_DIR/skills/gt-mesh-setup" "$SKILLS_DIR/gt-mesh-setup"
  echo "       gt-mesh-setup skill installed"
fi

echo "       Skills dir: $SKILLS_DIR"

# Step 3: Add Excalidraw MCP server
echo ""
echo "[3/5] Configuring Excalidraw MCP server..."
if [ -f "$MCP_CONFIG" ]; then
  # Check if excalidraw already configured
  if grep -q "excalidraw" "$MCP_CONFIG" 2>/dev/null; then
    echo "       Excalidraw MCP already configured"
  else
    echo "       Add this to $MCP_CONFIG manually:"
    echo '       "excalidraw": { "type": "url", "url": "https://mcp.excalidraw.com" }'
  fi
else
  echo "       No MCP config found at $MCP_CONFIG"
  echo "       To add Excalidraw MCP, create $MCP_CONFIG with:"
  echo '       { "mcpServers": { "excalidraw": { "type": "url", "url": "https://mcp.excalidraw.com" } } }'
fi

# Step 4: Make mesh scripts executable and detect platform
echo ""
echo "[4/6] Setting up mesh commands..."
if [ -d "$INSTALL_DIR/scripts" ]; then
  chmod +x "$INSTALL_DIR/scripts/"*.sh 2>/dev/null || true
  echo "       Scripts made executable"
fi

# Create symlink so `gt mesh` works (if gt supports plugins)
if [ -d "$GT_ROOT/mayor" ]; then
  mkdir -p "$GT_ROOT/.gt-plugins"
  ln -sf "$INSTALL_DIR/scripts/mesh.sh" "$GT_ROOT/.gt-plugins/mesh" 2>/dev/null || true
  echo "       Mesh commands linked"
fi

# Step 5: Detect platform and install integration
echo ""
echo "[5/6] Detecting platform..."

# Check for original gastown (Go-based, has internal/ dir or go.mod)
if [ -f "$GT_ROOT/go.mod" ] || [ -d "$GT_ROOT/internal/plugin" ]; then
  echo "       Detected: steveyegge/gastown (Go)"
  if [ -d "$INSTALL_DIR/integrations/gastown" ]; then
    mkdir -p "$GT_ROOT/plugins/gt-mesh-sync"
    cp "$INSTALL_DIR/integrations/gastown/plugin.md" "$GT_ROOT/plugins/gt-mesh-sync/plugin.md"
    echo "       Installed gastown daemon plugin at plugins/gt-mesh-sync/"
  fi
# Check for gasclaw (has src/gasclaw/ or gasclaw.yaml)
elif [ -d "$GT_ROOT/src/gasclaw" ] || [ -f "$GT_ROOT/gasclaw.yaml" ] || [ -f "/workspace/config/gasclaw.yaml" ]; then
  echo "       Detected: gasclaw"
  if [ -d "$INSTALL_DIR/integrations/gasclaw" ]; then
    OPENCLAW_SKILLS="${HOME}/.openclaw/skills"
    mkdir -p "$OPENCLAW_SKILLS/gt-mesh-sync"
    cp "$INSTALL_DIR/integrations/gasclaw/SKILL.md" "$OPENCLAW_SKILLS/gt-mesh-sync/SKILL.md"
    echo "       Installed gasclaw skill at $OPENCLAW_SKILLS/gt-mesh-sync/"
  fi
else
  echo "       Platform: generic Gas Town"
  echo "       Manual integration available at: $INSTALL_DIR/integrations/"
fi

# Step 6: Show next steps
echo ""
echo "[6/6] Done!"
echo ""
echo "========================================="
echo "  GT Mesh installed successfully!"
echo "========================================="
echo ""
echo "Next steps:"
echo ""
echo "  # Initialize mesh (become coordinator):"
echo "  gt mesh init"
echo ""
echo "  # Or join an existing mesh:"
echo "  gt mesh join <invite-code>"
echo ""
echo "  # Check status:"
echo "  gt mesh status"
echo ""
echo "  # Invite a friend:"
echo "  gt mesh invite --role write --expires 7d"
echo ""
echo "Documentation: https://github.com/Deepwork-AI/gt-mesh/blob/main/docs/DOCUMENTATION.md"
echo "Architecture:  https://github.com/Deepwork-AI/gt-mesh/blob/main/docs/ARCHITECTURE.md"
echo ""
