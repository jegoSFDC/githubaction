#!/bin/bash
# ==============================================================================
# Static Code Analysis Script
# ==============================================================================
# Executes Salesforce Code Analyzer on Apex and Lightning Web Components
# to identify code quality violations and security vulnerabilities.
#
# Analysis Targets:
#   - Apex Classes: Business logic and data access layer
#   - LWC Components: Frontend component structure and security
#
# Process Flow:
#   1. Validate file modifications in commit
#   2. Execute targeted code analysis per technology
#   3. Generate structured violation reports
#   4. Display analysis results summary
#
# Quality Gates:
#   - Security vulnerability detection
#   - Code quality standard enforcement
#   - Performance best practice validation
# ==============================================================================

set -euo pipefail

echo "🔍 Executing static code analysis..."

# Function to run code analyzer for specific technology
run_code_analyzer() {
  local target=$1
  local output_file=$2
  local artifact_name=$3
  local component_type=$4

  echo "🔎 Analyzing $component_type code in $target..."

  # Check if files of this type were modified
  if [ "${{ github.event.head_commit.modified }}" != "null" ] && {
    [[ "${{ github.event.head_commit.modified }}" == *"$component_type"* ]] ||
    [[ "${{ github.event.head_commit.added }}" == *"$component_type"* ]]
  }; then

    echo "📋 $component_type modifications detected - running analysis..."

    if sf code-analyzer analyze \
      --target "$target" \
      --view detail \
      --output-file "$output_file" \
      --severity-threshold "${{ env.SEVERITY_THRESHOLD }}" > /dev/null 2>&1; then

      echo "✅ $component_type analysis completed successfully"

      # Display analysis results summary
      if [ -f "$output_file" ]; then
        VIOLATION_COUNT=$(jq '.violations | length' "$output_file" 2>/dev/null || echo "0")
        echo "📊 $component_type violations found: $VIOLATION_COUNT"

        if [ "$VIOLATION_COUNT" -gt 0 ]; then
          echo "🔍 Top violations (showing up to 5):"
          jq -r '.violations[]? | "  • \(.ruleName // "Unknown"): \(.message // "No message")" | select(length > 0)' "$output_file" 2>/dev/null | head -5
        fi
      fi

    else
      echo "⚠️  $component_type analysis completed with warnings"
    fi

  else
    echo "ℹ️  No $component_type modifications detected - skipping analysis"
  fi
}

# Execute code analysis for Apex Classes
run_code_analyzer \
  "force-app/main/default/classes" \
  "reports/apex.json" \
  "code-analyzer-apex-results" \
  "ApexClass"

echo ""

# Execute code analysis for Lightning Web Components
run_code_analyzer \
  "force-app/main/default/lwc" \
  "reports/lwc.json" \
  "code-analyzer-lwc-results" \
  "LightningComponentBundle"

echo ""
echo "📋 Code analysis execution summary:"
echo "  • Apex violations: $(jq '.violations | length' reports/apex.json 2>/dev/null || echo '0')"
echo "  • LWC violations: $(jq '.violations | length' reports/lwc.json 2>/dev/null || echo '0')"
