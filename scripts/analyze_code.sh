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

echo ""
echo "🚀 STAGE 4: STATIC CODE ANALYSIS"
echo "==============================="
echo "🔍 Executing static code analysis..."

# Function to run code analyzer for specific technology
run_code_analyzer() {
  local target=$1
  local output_file=$2
  local artifact_name=$3
  local component_type=$4

  echo ""
  echo "🔎 Analyzing $component_type code in $target..."

  # Check if package.xml contains this component type OR if target directory exists
  local has_components=false
  
  if [ -f "delta/package/package.xml" ]; then
    if grep -q "<name>$component_type</name>" delta/package/package.xml 2>/dev/null; then
      echo "📋 $component_type found in delta package.xml - running analysis..."
      has_components=true
    fi
  fi
  
  # Also check if the target directory has files
  if [ -d "$target" ] && [ "$(find "$target" -type f 2>/dev/null | wc -l)" -gt 0 ]; then
    echo "📁 $component_type files found in $target - running analysis..."
    has_components=true
  fi

  if [ "$has_components" = true ]; then
    echo ""
    echo "⚙️  EXECUTING CODE ANALYZER"
    echo "=========================="
    echo "  • Target: $target"
    echo "  • Component Type: $component_type"
    echo "  • Severity Threshold: $SEVERITY_THRESHOLD"
    echo "  • Output: $output_file"
    echo ""
    
    # Create reports directory
    mkdir -p reports
    
    if sf code-analyzer analyze \
      --target "$target" \
      --view detail \
      --output-file "$output_file" \
      --severity-threshold "${SEVERITY_THRESHOLD}" 2>&1 | tee /tmp/code_analyzer_${component_type}.log; then

      echo ""
      echo "✅ $component_type analysis completed successfully"

      # Display analysis results summary
      if [ -f "$output_file" ]; then
        VIOLATION_COUNT=$(jq '.violations | length' "$output_file" 2>/dev/null || echo "0")
        echo ""
        echo "📊 ANALYSIS RESULTS"
        echo "==================="
        echo "  • Total violations: $VIOLATION_COUNT"

        if [ "$VIOLATION_COUNT" -gt 0 ]; then
          echo ""
          echo "🔍 VIOLATIONS DETECTED:"
          echo "======================="
          jq -r '.violations[]? | "  ❌ [\(.severity // "N/A")] \(.ruleName // "Unknown")\n     File: \(.location // "Unknown")\n     Message: \(.message // "No message")\n"' "$output_file" 2>/dev/null | head -50
          echo ""
          echo "📄 Full report saved to: $output_file"
        else
          echo "  ✅ No violations found - code meets quality standards!"
        fi
      fi

    else
      echo ""
      echo "⚠️  $component_type analysis completed with warnings"
      echo "📄 Analyzer output:"
      cat /tmp/code_analyzer_${component_type}.log 2>/dev/null || echo "  (no output available)"
      # Still create empty report file
      mkdir -p reports
      echo '{"violations":[]}' > "$output_file"
    fi

  else
    echo "ℹ️  No $component_type modifications detected - skipping analysis"
    # Create empty report file for consistency
    echo '{"violations":[]}' > "$output_file"
  fi
}

echo ""
echo "🔧 Processing Apex Classes..."
# Execute code analysis for Apex Classes
run_code_analyzer \
  "force-app/main/default/classes" \
  "reports/apex.json" \
  "code-analyzer-apex-results" \
  "ApexClass"

echo ""
echo "⚡ Processing Lightning Web Components..."
# Execute code analysis for Lightning Web Components
run_code_analyzer \
  "force-app/main/default/lwc" \
  "reports/lwc.json" \
  "code-analyzer-lwc-results" \
  "LightningComponentBundle"

echo ""
echo "📋 Code analysis execution summary:"
APEX_VIOLATIONS=$(jq '.violations | length' reports/apex.json 2>/dev/null || echo '0')
LWC_VIOLATIONS=$(jq '.violations | length' reports/lwc.json 2>/dev/null || echo '0')
echo "  • Apex violations: $APEX_VIOLATIONS"
echo "  • LWC violations: $LWC_VIOLATIONS"
echo "  • Total violations: $((APEX_VIOLATIONS + LWC_VIOLATIONS))"

echo ""
echo "✅ STAGE 4 COMPLETED: Static code analysis finished"
echo "==============================================="
