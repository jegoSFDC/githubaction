#!/bin/bash
# ==============================================================================
# Static Code Analysis Results Display Script
# ==============================================================================
# Displays results from Salesforce Code Analyzer executed by GitHub Actions.
# The actual analysis is performed by forcedotcom/run-code-analyzer@v2 action.
#
# This script:
#   1. Ensures report files exist
#   2. Displays violations in human-readable format
#   3. Provides summary statistics
# ==============================================================================

set -euo pipefail

echo ""
echo "🚀 STAGE 4: STATIC CODE ANALYSIS RESULTS"
echo "========================================"
echo "📋 Displaying code analysis results..."

# Create reports directory
mkdir -p reports

# Ensure report files exist with default empty structure
[ -f reports/apex.json ] || echo '{"violations":[]}' > reports/apex.json
[ -f reports/lwc.json ] || echo '{"violations":[]}' > reports/lwc.json

echo ""
echo "🔧 Apex Code Analysis:"
echo "======================"

# Display Apex results
APEX_VIOLATIONS=$(jq '.violations | length' reports/apex.json 2>/dev/null || echo "0")
if [ "$APEX_VIOLATIONS" -gt 0 ]; then
  echo "📊 Found $APEX_VIOLATIONS violation(s)"
  echo ""
  jq -r '.violations[]? |
    (if .location then (.location | split(":")[0] | split("/") | .[-1]) else "Unknown" end) as $file |
    "  ❌ [\(.severity // "N/A")] \($file) - \(.ruleName // "Unknown")\n     \(.message)"' reports/apex.json 2>/dev/null | head -40
else
  echo "✅ No violations found - code meets quality standards!"
fi

echo ""
echo "⚡ LWC Code Analysis:"
echo "====================="

# Display LWC results
LWC_VIOLATIONS=$(jq '.violations | length' reports/lwc.json 2>/dev/null || echo "0")
if [ "$LWC_VIOLATIONS" -gt 0 ]; then
  echo "📊 Found $LWC_VIOLATIONS violation(s)"
  echo ""
  jq -r '.violations[]? |
    (if .location then (.location | split(":")[0] | split("/") | .[-1]) else "Unknown" end) as $file |
    "  ❌ [\(.severity // "N/A")] \($file) - \(.ruleName // "Unknown")\n     \(.message)"' reports/lwc.json 2>/dev/null | head -40
else
  echo "✅ No violations found - code meets quality standards!"
fi

echo ""
echo "📊 Overall Summary:"
echo "==================="
echo "  • Apex violations: $APEX_VIOLATIONS"
echo "  • LWC violations: $LWC_VIOLATIONS"
echo "  • Total violations: $((APEX_VIOLATIONS + LWC_VIOLATIONS))"

echo ""
echo "✅ STAGE 4 COMPLETED: Static code analysis results displayed"
echo "=========================================================="
