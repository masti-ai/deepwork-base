# blueprint.yaml — Mesh Blueprint Specification v1
#
# A blueprint is a shareable bundle of mesh knowledge.
# Blueprints are published to the DoltHub registry and installable by any mesh node.
#
# Blueprint types:
#   - Skills:     Claude Code SKILL.md files (installed to ~/.claude/skills/)
#   - Roles:      Behavioral role definitions (planner, worker, reviewer, custom)
#   - Rules:      Governance rule sets (branch naming, PR requirements, etc.)
#   - Templates:  PR bodies, config templates, workflow templates
#   - Knowledge:  Docs, patterns, conventions, shared memory, tips
#
# A single blueprint can bundle any combination of these.
# Think of it as npm packages, but for AI agent knowledge.

# --- REQUIRED FIELDS ---
name: "my-blueprint"                   # Unique blueprint name (lowercase, hyphens ok)
version: "1.0.0"                       # Semver
description: "What this blueprint provides" # One-line description

# --- AUTHOR ---
author: "gt-local"                     # GT ID of publisher
author_github: "freebird-ai"           # GitHub username for attribution
tags: "backend, devops, rules"         # Comma-separated search tags

# --- CONTENTS ---
# List files under each section. Paths are relative to the blueprint directory.
# Empty sections are ok — a blueprint can contain just skills, or just knowledge.

skills:
  # Each skill is a directory with a SKILL.md file
  # Installed to: ~/.claude/skills/<skill-name>/SKILL.md
  - skills/my-skill/SKILL.md
  - skills/another-skill/SKILL.md

roles:
  # Role YAML files defining behavioral defaults
  # Installed to: $GT_ROOT/.mesh-config/roles/
  - roles/devops-lead.yaml
  - roles/qa-engineer.yaml

rules:
  # Governance rule YAML files
  # Can be applied to mesh_rules DoltHub table
  - rules/strict-review.yaml
  - rules/branch-naming.yaml

templates:
  # Reusable templates (PR bodies, config files, etc.)
  # Installed to: $GT_ROOT/.mesh-config/templates/
  - templates/pr-body.md
  - templates/hotfix-pr.md

knowledge:
  # Docs, patterns, shared memory, conventions
  # Installed to: $GT_ROOT/.mesh-config/knowledge/
  - knowledge/patterns.md
  - knowledge/conventions.md
  - knowledge/troubleshooting.md

# --- OPTIONAL ---

# Dependencies on other blueprints (installed first)
# depends:
#   - "deepwork-base>=1.0.0"

# Post-install hook (bash script to run after install)
# post_install: "scripts/setup.sh"

# Minimum mesh config version required
# requires_config_version: 1
