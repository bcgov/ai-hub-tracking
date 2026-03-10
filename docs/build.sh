#!/bin/bash
# Build script for documentation pages
# Combines header + page content + footer into final HTML files

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARTIALS_DIR="$SCRIPT_DIR/_partials"
PAGES_DIR="$SCRIPT_DIR/_pages"

# Get current date/time dynamically from system
CURRENT_YEAR=$(date +%Y)
CURRENT_MONTH=$(date +%Y-%m)
CURRENT_DATE=$(date +%Y-%m-%d)

echo "Building documentation pages..."
echo "  Date: $CURRENT_DATE"

# Process each page in _pages directory
for page in "$PAGES_DIR"/*.html; do
    if [ -f "$page" ]; then
        filename=$(basename "$page")

        # Skip files starting with underscore (templates, partials)
        if [[ "$filename" == _* ]]; then
            echo "  Skipping template: $filename"
            continue
        fi
        pagename="${filename%.html}"

        echo "  Building: $filename"

        # Extract page metadata from comments at top of file
        # Format: <!-- TITLE: Page Title -->
        # Format: <!-- NAV: index -->
        page_title=$(grep -oP '<!--\s*TITLE:\s*\K[^-]+' "$page" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' || echo "Documentation")
        nav_active=$(grep -oP '<!--\s*NAV:\s*\K\w+' "$page" || echo "")

        # Read partials
        header=$(cat "$PARTIALS_DIR/header.html")
        footer=$(cat "$PARTIALS_DIR/footer.html")

        # Read page content (skip metadata comments)
        content=$(sed '/^<!--.*-->$/d' "$page")

        # Replace template variables in header
        header="${header//\{\{PAGE_TITLE\}\}/$page_title}"

        # Set active nav item FIRST (before clearing, so the active class survives)
        if [ -n "$nav_active" ]; then
            header="${header//\{\{NAV_${nav_active^^}\}\}/active}"
        fi

        # Clear all inactive nav items (already-active ones won't match these patterns)
        header="${header//\{\{NAV_INDEX\}\}/}"
        header="${header//\{\{NAV_OIDC\}\}/}"
        header="${header//\{\{NAV_TERRAFORM\}\}/}"
        header="${header//\{\{NAV_LANGUAGE-SERVICE-PII\}\}/}"
        header="${header//\{\{NAV_DOCUMENT-INTELLIGENCE\}\}/}"
        header="${header//\{\{NAV_WORKFLOWS\}\}/}"
        header="${header//\{\{NAV_DIAGRAMS\}\}/}"
        header="${header//\{\{NAV_TERRAFORM-REFERENCE\}\}/}"
        header="${header//\{\{NAV_APIM-KEY-ROTATION\}\}/}"
        header="${header//\{\{NAV_APIM-INTERNAL-ENDPOINTS\}\}/}"
        header="${header//\{\{NAV_PLAYBOOKS\}\}/}"
        header="${header//\{\{NAV_DECISIONS\}\}/}"
        header="${header//\{\{NAV_COST\}\}/}"
        header="${header//\{\{NAV_FAQ\}\}/}"
        header="${header//\{\{NAV_SERVICES\}\}/}"
        header="${header//\{\{NAV_TECHDEEP\}\}/}"

        # Replace date variables in footer
        footer="${footer//\{\{YEAR\}\}/$CURRENT_YEAR}"

        # Replace date variables in content (for pages that need dynamic dates)
        content="${content//\{\{YEAR\}\}/$CURRENT_YEAR}"
        content="${content//\{\{CURRENT_MONTH\}\}/$CURRENT_MONTH}"
        content="${content//\{\{CURRENT_DATE\}\}/$CURRENT_DATE}"

        # Combine and write output
        echo "$header" > "$SCRIPT_DIR/$filename"
        echo "$content" >> "$SCRIPT_DIR/$filename"
        echo "$footer" >> "$SCRIPT_DIR/$filename"
    fi
done

echo "Build complete! Generated files:"
ls -la "$SCRIPT_DIR"/*.html 2>/dev/null || echo "  No HTML files generated"

# Generate full-text search index (assets/search-index.json)
# Requires Node.js (no external npm packages needed)
echo ""
echo "Generating search index..."
NODE_BIN=""
if command -v node &>/dev/null; then
    NODE_BIN="node"
elif command -v node.exe &>/dev/null; then
    NODE_BIN="node.exe"
fi

if [ -n "$NODE_BIN" ]; then
    if [ "$NODE_BIN" = "node.exe" ] && command -v wslpath &>/dev/null; then
        # node.exe is a Windows binary; convert WSL paths to Windows paths
        $NODE_BIN "$(wslpath -w "$SCRIPT_DIR/generate-search-index.js")" "$(wslpath -w "$SCRIPT_DIR")"
    else
        $NODE_BIN "$SCRIPT_DIR/generate-search-index.js" "$SCRIPT_DIR"
    fi
else
    echo "  WARNING: Node.js not found – search index was NOT generated."
fi
