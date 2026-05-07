#!/bin/bash
# skills/skill-init.sh
# Scaffold a Claude Code skill at .claude/skills/<name>/ (project-local, default)
# or ~/.claude/skills/<name>/ (--global).
#
# USAGE
#   cc-skill-init <name> [flags]
#
# FLAGS
#   -d, --description "<text>"   One-line description (used by Claude to decide when to invoke)
#   -t, --type <type>            analyzer | generator | interactive | hook  (informational)
#       --reads <path>           File the skill must read first. Can repeat.
#       --opc                    Shortcut: --reads .agents/product-marketing-context.md
#                                          --reads .agents/voice-of-customer.md
#       --global                 Create at ~/.claude/skills/ instead of ./.claude/skills/
#       --force                  Overwrite existing dir if present (asks first unless --yes)
#   -y, --yes                    Skip confirmations
#   -h, --help                   Show this help
#
# EXAMPLES
#   cc-skill-init voc-collect -d "Mine customer quotes from Reddit/G2/X" --opc
#   cc-skill-init seo-write -d "Draft SEO blog from outline + voice" --reads .agents/voice-of-customer.md
#   cc-skill-init my-skill --global
#
# OUTPUT
#   .claude/skills/<name>/
#   ├── SKILL.md       — frontmatter + Step 0 (read-context-first) + workflow placeholders
#   ├── README.md      — for humans: what this skill does, when to use, how to evolve
#   ├── prompts/
#   │   └── starter.md — example prompt the skill author can iterate on
#   ├── templates/.gitkeep
#   └── examples/.gitkeep

set -e

NAME=""
DESCRIPTION=""
TYPE="analyzer"
READS=()
OPC_DEFAULTS=0
GLOBAL=0
FORCE=0
YES=0

show_help() {
  sed -n '2,33p' "$0" | sed 's/^# \?//'
}

# ── Parse args ──────────────────────────────────────────────────────────────
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)         show_help; exit 0 ;;
    -d|--description)  DESCRIPTION="$2"; shift 2 ;;
    -t|--type)         TYPE="$2"; shift 2 ;;
       --reads)        READS+=("$2"); shift 2 ;;
       --opc)          OPC_DEFAULTS=1; shift ;;
       --global)       GLOBAL=1; shift ;;
       --force)        FORCE=1; shift ;;
    -y|--yes)          YES=1; shift ;;
    -*)                echo "unknown flag: $1" >&2; exit 1 ;;
    *)                 if [ -z "$NAME" ]; then NAME="$1"; else echo "extra arg: $1" >&2; exit 1; fi; shift ;;
  esac
done

# ── Validate ────────────────────────────────────────────────────────────────
if [ -z "$NAME" ]; then
  echo "error: skill name required" >&2
  echo "" >&2
  show_help >&2
  exit 1
fi

if ! [[ "$NAME" =~ ^[a-z][a-z0-9-]*$ ]]; then
  echo "error: skill name must be lowercase letters/digits/hyphens, starting with a letter (got '$NAME')" >&2
  exit 1
fi

if [ "$OPC_DEFAULTS" -eq 1 ]; then
  if [ ${#READS[@]} -eq 0 ]; then
    READS+=(".agents/product-marketing-context.md")
    READS+=(".agents/voice-of-customer.md")
  fi
fi

if [ -z "$DESCRIPTION" ]; then
  DESCRIPTION="(TODO: one-line description used by Claude to decide when to invoke this skill)"
fi

# ── Resolve target dir ──────────────────────────────────────────────────────
if [ "$GLOBAL" -eq 1 ]; then
  ROOT="$HOME/.claude/skills"
else
  ROOT="$(pwd)/.claude/skills"
fi

DIR="$ROOT/$NAME"

if [ -d "$DIR" ]; then
  if [ "$FORCE" -eq 0 ]; then
    echo "error: $DIR already exists. Pass --force to overwrite." >&2
    exit 1
  fi
  if [ "$YES" -eq 0 ]; then
    printf "Overwrite %s? [y/N] " "$DIR"
    read -r ans
    [[ "$ans" =~ ^[Yy] ]] || { echo "aborted"; exit 1; }
  fi
  rm -rf "$DIR"
fi

mkdir -p "$DIR/prompts" "$DIR/templates" "$DIR/examples"
touch "$DIR/templates/.gitkeep" "$DIR/examples/.gitkeep"

# ── Generate SKILL.md ───────────────────────────────────────────────────────
TODAY=$(date +%Y-%m-%d)

# Build the reads block as YAML + markdown bullet list
READS_YAML=""
READS_MD=""
if [ ${#READS[@]} -gt 0 ]; then
  READS_YAML="reads_first:"$'\n'
  for r in "${READS[@]}"; do
    READS_YAML+="  - $r"$'\n'
    READS_MD+="- \`$r\`"$'\n'
  done
fi

# Capitalize first letter of name for human title (portable: works on BSD + GNU)
TITLE_CASE=$(echo "$NAME" | awk '{ print toupper(substr($0,1,1)) substr($0,2) }' | tr '-' ' ')

cat > "$DIR/SKILL.md" <<EOF
---
name: $NAME
description: $DESCRIPTION
type: $TYPE
created: $TODAY
${READS_YAML}---

# $TITLE_CASE

> $DESCRIPTION

EOF

if [ -n "$READS_MD" ]; then
  cat >> "$DIR/SKILL.md" <<EOF
## Step 0 · Context check (READ FIRST)

Before doing anything else, read these files. If any are missing, ask the
user to create them first (e.g. via the \`product-marketing-context\` skill).

$READS_MD
EOF
fi

cat >> "$DIR/SKILL.md" <<'EOF'

## What I need from you

<!-- Replace with concrete inputs the user must provide. Examples:
  - "Paste the URL of the page you want me to optimize"
  - "Tell me the goal: traffic / leads / authority"
  - "Specify the target persona (or 'use the one in product-marketing-context')"
-->

## What I'll deliver

<!-- Replace with the concrete output format. Examples:
  - "A markdown file with H1, headline options, and full body draft"
  - "A bullet-point list of 5 hooks with reasoning"
-->

## Workflow

1. <!-- step 1 -->
2. <!-- step 2 -->
3. <!-- step 3 -->

## Templates

See `templates/` for output skeletons. Drop reusable formats there.

## Examples

See `examples/` for real past runs. Drop one in after the first successful use.

## Prompts

See `prompts/starter.md` for the prompt I use to invoke this skill.
EOF

# ── Generate README.md ──────────────────────────────────────────────────────
cat > "$DIR/README.md" <<EOF
# Skill: $NAME

> $DESCRIPTION

**Type**: $TYPE
**Created**: $TODAY
EOF

if [ ${#READS[@]} -gt 0 ]; then
  cat >> "$DIR/README.md" <<EOF
**Reads first**:
$READS_MD
EOF
fi

cat >> "$DIR/README.md" <<EOF

## When to use

<!-- Add concrete trigger conditions. Examples:
  - "Once a week, when I want to refresh my customer-quote bank"
  - "Every time I'm about to write a new landing page"
  - "When a customer churns, to capture the reason"
-->

## How to invoke

\`\`\`
/$NAME
\`\`\`

Or trigger via natural language — Claude will pick this skill up if your
ask matches the description.

## How to evolve this skill

1. After each use, drop the run into \`examples/\`
2. If you find yourself repeating yourself, extract a template into \`templates/\`
3. Update \`SKILL.md\` workflow when you discover a better order
4. Cross-reference related skills in this section as you build them
EOF

# ── Generate starter prompt ─────────────────────────────────────────────────
cat > "$DIR/prompts/starter.md" <<EOF
# Starter prompt for skill: $NAME

> Iterate this prompt as you discover what works.

---

I want you to act as the **$NAME** skill: $DESCRIPTION
EOF

if [ ${#READS[@]} -gt 0 ]; then
  cat >> "$DIR/prompts/starter.md" <<EOF

First, read these files for context:
$READS_MD
EOF
fi

cat >> "$DIR/prompts/starter.md" <<'EOF'

Then ask me for the inputs you need.

After producing output, save the run to `examples/<date>-<topic>.md`.
EOF

# ── Output ──────────────────────────────────────────────────────────────────
GREEN=$'\033[32m'; DIM=$'\033[2m'; BOLD=$'\033[1m'; RESET=$'\033[0m'

printf '%s✓ Created skill at:%s %s\n' "$GREEN" "$RESET" "$DIR"
echo ""
echo "  $DIR/"
echo "  ├── SKILL.md         ← edit this with your workflow"
echo "  ├── README.md        ← for humans"
echo "  ├── prompts/"
echo "  │   └── starter.md"
echo "  ├── templates/"
echo "  └── examples/"
echo ""
printf '%sNext steps:%s\n' "$BOLD" "$RESET"
echo "  1. Edit $DIR/SKILL.md — fill in 'What I need', 'What I deliver', 'Workflow'"
echo "  2. (Optional) Add a real example to $DIR/examples/"
echo "  3. In Claude Code, type /$NAME to invoke"
if [ "$GLOBAL" -eq 0 ]; then
  echo ""
  printf '%s%s%s\n' "$DIM" "Tip: skills under .claude/skills/ are project-local and committed with the project." "$RESET"
  printf '%s%s%s\n' "$DIM" "     Use --global to put a skill at ~/.claude/skills/ for use everywhere." "$RESET"
fi
