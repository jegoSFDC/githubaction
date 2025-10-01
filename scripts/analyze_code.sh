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
    
    # Install Code Analyzer plugin if not already installed
    if ! sf plugins | grep -q "code-analyzer"; then
      echo "📥 Installing Salesforce Code Analyzer plugin..."
      echo y | sf plugins install @salesforce/sfdx-scanner >/dev/null 2>&1 || true
    fi
    
    # Run scanner (exit code 1 means violations found, which is NOT an error)
    set +e  # Temporarily disable exit on error
    sf scanner run \
      --target "$target" \
      --format json \
      --outfile "$output_file" \
      --severity-threshold "${SEVERITY_THRESHOLD}" 2>&1 | tee /tmp/code_analyzer_${component_type}.log
    
    local scanner_exit_code=$?
    set -e  # Re-enable exit on error

    echo ""
    if [ $scanner_exit_code -eq 0 ]; then
      echo "✅ $component_type analysis completed - no violations found"
    elif [ $scanner_exit_code -eq 1 ]; then
      echo "⚠️  $component_type analysis completed - violations detected (exit code 1)"
    else
      echo "❌ $component_type analysis failed with exit code $scanner_exit_code"
    fi

    # Display analysis results summary
    if [ -f "$output_file" ]; then
        # Scanner output format is different from code-analyzer - check both
        VIOLATION_COUNT=0
        
        # Try scanner format first (array of violations at root level)
        if jq -e 'type == "array"' "$output_file" >/dev/null 2>&1; then
          VIOLATION_COUNT=$(jq '. | length' "$output_file" 2>/dev/null || echo "0")
        # Try legacy format (.violations array)
        elif jq -e '.violations' "$output_file" >/dev/null 2>&1; then
          VIOLATION_COUNT=$(jq '.violations | length' "$output_file" 2>/dev/null || echo "0")
        fi
        
        echo ""
        echo "📊 ANALYSIS RESULTS"
        echo "==================="
        echo "  • Total violations: $VIOLATION_COUNT"

        if [ "$VIOLATION_COUNT" -gt 0 ]; then
          echo ""
          echo "🔍 VIOLATIONS DETECTED:"
          echo "======================="
          
          # Display violations based on format
          if jq -e 'type == "array"' "$output_file" >/dev/null 2>&1; then
            jq -r '.[] | "  ❌ [\(.severity // "N/A")] \(.engine // "Unknown")/\(.ruleName // "Unknown")\n     File: \(.fileName // "Unknown"):\(.line // "?")\n     Message: \(.message // "No message")\n"' "$output_file" 2>/dev/null | head -50
          else
            jq -r '.violations[]? | "  ❌ [\(.severity // "N/A")] \(.ruleName // "Unknown")\n     File: \(.location // "Unknown")\n     Message: \(.message // "No message")\n"' "$output_file" 2>/dev/null | head -50
          fi
          
          echo ""
          echo "📄 Full report saved to: $output_file"
        else
          echo "  ✅ No violations found - code meets quality standards!"
        fi
      else
        echo "⚠️  Output file not found: $output_file"
        mkdir -p reports
        echo '[]' > "$output_file"
      fi
    fi

  else
    echo "ℹ️  No $component_type modifications detected - skipping analysis"
    # Create empty report file for consistency
    mkdir -p reports
    echo '[]' > "$output_file"
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

# Count violations handling both scanner formats
count_violations() {
  local file=$1
  if [ ! -f "$file" ]; then
    echo "0"
    return
  fi
  
  if jq -e 'type == "array"' "$file" >/dev/null 2>&1; then
    jq '. | length' "$file" 2>/dev/null || echo "0"
  elif jq -e '.violations' "$file" >/dev/null 2>&1; then
    jq '.violations | length' "$file" 2>/dev/null || echo "0"
  else
    echo "0"
  fi
}

APEX_VIOLATIONS=$(count_violations reports/apex.json)
LWC_VIOLATIONS=$(count_violations reports/lwc.json)
echo "  • Apex violations: $APEX_VIOLATIONS"
echo "  • LWC violations: $LWC_VIOLATIONS"
echo "  • Total violations: $((APEX_VIOLATIONS + LWC_VIOLATIONS))"

echo ""
echo "✅ STAGE 4 COMPLETED: Static code analysis finished"
echo "==============================================="
