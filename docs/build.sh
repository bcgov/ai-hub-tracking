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
        page_title=$(grep -oP '<!--\s*TITLE:\s*\K[^-]+' "$page" | tr -d ' ' || echo "Documentation")
        nav_active=$(grep -oP '<!--\s*NAV:\s*\K\w+' "$page" || echo "")

        # Read partials
        header=$(cat "$PARTIALS_DIR/header.html")
        footer=$(cat "$PARTIALS_DIR/footer.html")

        # Read page content (skip metadata comments)
        content=$(sed '/^<!--.*-->$/d' "$page")

        # Replace template variables in header
        header="${header//\{\{PAGE_TITLE\}\}/$page_title}"

        # Set active nav item
        header="${header//\{\{NAV_INDEX\}\}/}"
        header="${header//\{\{NAV_OIDC\}\}/}"
        header="${header//\{\{NAV_TERRAFORM\}\}/}"
        header="${header//\{\{NAV_LANGUAGE-SERVICE-PII\}\}/}"
        header="${header//\{\{NAV_DOCUMENT-INTELLIGENCE\}\}/}"
        header="${header//\{\{NAV_WORKFLOWS\}\}/}"
        header="${header//\{\{NAV_DIAGRAMS\}\}/}"
        header="${header//\{\{NAV_TERRAFORM-REFERENCE\}\}/}"
        header="${header//\{\{NAV_PLAYBOOKS\}\}/}"
        header="${header//\{\{NAV_DECISIONS\}\}/}"
        header="${header//\{\{NAV_COST\}\}/}"
        header="${header//\{\{NAV_FAQ\}\}/}"

        if [ -n "$nav_active" ]; then
            header="${header//\{\{NAV_${nav_active^^}\}\}/active}"
        fi

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
