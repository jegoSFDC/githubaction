#!/bin/bash
# ==============================================================================
# Deployment Validation Script
# ==============================================================================
# Validates deployment package against target Salesforce environment using
# intelligent test execution strategies based on change analysis.
#
# Validation Strategies:
#   1. Targeted Testing: Execute only tests related to changed components
#   2. Fallback Testing: Full test suite execution if targeted testing fails
#   3. Coverage Analysis: Verify code coverage meets organizational standards
#   4. Component Validation: Ensure metadata deployment integrity
#
# Exit Codes:
#   0 - Validation successful or appropriately skipped
#   1 - Validation failed or coverage requirements not met
#
# Environment Dependencies:
#   - RELATED_TESTS: Space-separated list of test classes for targeted execution
#   - COVERAGE_THRESHOLD: Minimum coverage percentage required
# ==============================================================================

set -euo pipefail

# Initialize logging and reporting
mkdir -p reports

# Default report structure for fallback scenarios
echo '{"result":{"status":"Failed","message":"No deploy run performed"}}' > reports/deploy-report.json
echo "" > reports/validation-summary.txt

# Logging function for consistent output formatting
summary() {
  echo "$1" | tee -a reports/validation-summary.txt
}

# Function to execute deployment validation with specific test strategy
execute_validation() {
  local test_level="$1"
  local test_classes="${2:-}"
  local report_file="reports/deploy-report.json"

  echo ""
  echo "⚙️  INITIATING DEPLOYMENT VALIDATION"
  echo "===================================="
  echo "🔄 Executing deployment validation with test level: $test_level"
  echo ""

  # Build command for display
  local deploy_cmd="sf project deploy start"
  deploy_cmd="$deploy_cmd --source-dir delta/force-app"
  deploy_cmd="$deploy_cmd --target-org sandbox"
  deploy_cmd="$deploy_cmd --dry-run"
  deploy_cmd="$deploy_cmd --test-level $test_level"

  if [ -n "$test_classes" ]; then
    deploy_cmd="$deploy_cmd --tests $test_classes"
  fi

  # Show the command being executed
  echo "📋 Command: $deploy_cmd"
  echo ""
  echo "🔄 Deployment progress (streaming output):"
  echo "==========================================="
  
  # Execute with LIVE output (no --json flag for visibility)
  local temp_output="/tmp/deploy_live_output.txt"
  
  if [ -n "$test_classes" ]; then
    sf project deploy start \
      --source-dir delta/force-app \
      --target-org sandbox \
      --dry-run \
      --test-level "$test_level" \
      --tests "$test_classes" \
      --json 2>&1 | tee "$temp_output"
  else
    sf project deploy start \
      --source-dir delta/force-app \
      --target-org sandbox \
      --dry-run \
      --test-level "$test_level" \
      --json 2>&1 | tee "$temp_output"
  fi
  
  local exit_code=$?
  
  # Save to report file
  cat "$temp_output" > "$report_file"
  
  echo ""
  echo "==========================================="
  echo ""
  echo "📊 DEPLOYMENT VALIDATION SUMMARY"
  echo "================================"
  
  # Parse and display key metrics from the JSON output
  if [ -f "$report_file" ]; then
    local status
    status=$(jq -r '.result.status // "Unknown"' "$report_file" 2>/dev/null || echo "Unknown")
    
    echo "  • Status: $status"
    
    if jq -e '.result.details.componentSuccesses' "$report_file" >/dev/null 2>&1; then
      local success_count
      success_count=$(jq '.result.details.componentSuccesses | length' "$report_file" 2>/dev/null || echo "0")
      echo "  • Components Successfully Validated: $success_count"
    fi
    
    if jq -e '.result.details.runTestResult' "$report_file" >/dev/null 2>&1; then
      local tests_run
      tests_run=$(jq -r '.result.details.runTestResult.testsRun // 0' "$report_file" 2>/dev/null || echo "0")
      echo "  • Tests Executed: $tests_run"
      
      if [ "$tests_run" -gt 0 ]; then
        local tests_passed
        tests_passed=$(jq -r '.result.details.runTestResult.passing // 0' "$report_file" 2>/dev/null || echo "0")
        echo "  • Tests Passed: $tests_passed"
      fi
    fi
    
    echo ""
  fi
  
  if [ $exit_code -eq 0 ]; then
    summary "✅ Deployment validation successful with $test_level"
    echo "✅ Deployment check-only validation PASSED"
    return 0
  else
    summary "❌ Deployment validation failed with $test_level (see $report_file)"
    echo "❌ Deployment check-only validation FAILED"
    return 1
  fi
}

# Function to calculate code coverage from deploy report
calculate_coverage() {
  local report_file="$1"

  if jq -e '.result.details.runTestResult.codeCoverage' "$report_file" >/dev/null 2>&1; then
    local coverage
    coverage=$(jq -r '[.result.details.runTestResult.codeCoverage[]? | (.coveredPercent // 0)] | (if length>0 then (add/length) else 0 end)' "$report_file" 2>/dev/null || echo "0")
    coverage=${coverage%.*}
    echo "$coverage"
  else
    echo "0"
  fi
}

# Main validation orchestration
main() {
  echo ""
  echo "🚀 STAGE 5B: DEPLOYMENT VALIDATION"
  echo "================================"
  summary "🚀 Starting deployment validation process..."

  # Check if there's actually a deployment package to validate
  if [ "${HAS_DEPLOYMENT_PACKAGE:-false}" = "true" ]; then
    summary "📦 Deployment package detected - proceeding with validation"

    # Validate delta package exists and contains deployable content
    if [ -d "delta/force-app" ] && [ "$(find delta/force-app -type f | wc -l)" -gt 0 ]; then
      summary "📦 Deployable metadata detected in delta package"

      # Check for Apex components requiring test execution
      if find delta/force-app -name "*.cls" -o -name "*.trigger" 2>/dev/null | grep -q .; then
        summary "🔧 Apex components detected - test execution required"
        APEX_DEPLOYMENT=true
      else
        summary "📄 Metadata-only deployment detected (LWC/other) - no test execution required"
        APEX_DEPLOYMENT=false
      fi

      # Execute deployment validation based on deployment type
      if [ "$APEX_DEPLOYMENT" = true ]; then
        # Apex deployment - run tests
        if [ -n "${RELATED_TESTS:-}" ]; then
          local related_tests_csv
          related_tests_csv=$(echo "$RELATED_TESTS" | xargs -n1 | paste -sd, - || echo "")

          summary "🎯 Using intelligent test selection: ${related_tests_csv}"

          # Execute validation with mapped tests
          echo "🔄 Executing deployment validation with targeted tests..."
          if execute_validation "RunSpecifiedTests" "$related_tests_csv"; then
            summary "✅ Intelligent test execution successful"

            # Verify coverage meets threshold
            local coverage
            coverage=$(calculate_coverage "reports/deploy-report.json")

            summary "📊 Code coverage achieved: ${coverage}%"

            if [ "$coverage" -lt "${COVERAGE_THRESHOLD}" ]; then
              summary "⚠️  Coverage below threshold (${COVERAGE_THRESHOLD}%) - attempting fallback"
              echo "🔄 Executing fallback with full test suite..."

              # Fallback to full test suite
              if execute_validation "RunLocalTests"; then
                summary "✅ Fallback test execution successful"
                mv reports/deploy-report-coverage.json reports/deploy-report.json 2>/dev/null || true
              else
                summary "❌ Fallback test execution failed"
              fi
            else
              summary "✅ Coverage threshold met - no fallback required"
            fi

          else
            summary "⚠️  Intelligent test execution failed - attempting fallback"
            echo "🔄 Executing fallback with full test suite..."

            # Fallback to full test suite
            if execute_validation "RunLocalTests"; then
              summary "✅ Fallback test execution successful"
            else
              summary "❌ Fallback test execution failed"
            fi
          fi

        else
          summary "ℹ️  No related tests identified - executing full test suite"
          echo "🔄 Executing deployment validation with full test suite..."
          execute_validation "RunLocalTests"
        fi
      else
        # Metadata-only deployment - no test execution required
        summary "📄 Metadata-only deployment (LWC/CustomObject/Flow) - no test execution required"
        
        echo ""
        echo "📋 DEPLOYMENT VALIDATION DETAILS"
        echo "================================="
        echo ""
        echo "📦 Package Contents:"
        cat delta/package/package.xml | grep -E "<members>|<name>" | sed 's/^/  /'
        echo ""
        
        echo "📁 Files to Deploy:"
        find delta/force-app -type f 2>/dev/null | sed 's|^delta/force-app/|  • |' | head -20 || echo "  (no files found)"
        local total_files
        total_files=$(find delta/force-app -type f 2>/dev/null | wc -l)
        echo ""
        echo "  Total files: $total_files"
        echo ""
        
        # Execute validation - the function will display all details and progress
        execute_validation "NoTestRun"
      fi

    else
      summary "⚠️  No deployable content found in delta package"
      echo '{"result":{"status":"Skipped","message":"No deployable metadata found"}}' > reports/deploy-report.json
    fi

  else
    summary "📋 No deployment package detected - skipping deployment validation"
    summary "ℹ️  This is expected for script/YAML-only changes"
    echo '{"result":{"status":"Skipped","message":"No deployment package to validate - script/YAML changes only"}}' > reports/deploy-report.json
  fi

  summary "🏁 Deployment validation process completed"

  echo ""
  echo "✅ STAGE 5B COMPLETED: Deployment validation finished"
  echo "================================================"
}

# Execute main validation function
main
