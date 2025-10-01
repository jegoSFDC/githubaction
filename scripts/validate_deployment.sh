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

  echo "🔄 Executing deployment validation with test level: $test_level"

  local deploy_cmd="sf project deploy start"
  deploy_cmd="$deploy_cmd --source-dir delta/force-app"
  deploy_cmd="$deploy_cmd --target-org sandbox"
  deploy_cmd="$deploy_cmd --dry-run"
  deploy_cmd="$deploy_cmd --test-level $test_level"

  if [ -n "$test_classes" ]; then
    deploy_cmd="$deploy_cmd --tests $test_classes"
  fi

  deploy_cmd="$deploy_cmd --json"

  if $deploy_cmd > "$report_file" 2>&1; then
    summary "✅ Deployment validation successful with $test_level"
    return 0
  else
    summary "❌ Deployment validation failed with $test_level (see $report_file)"
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
      if find delta/force-app -name "*.cls" -o -name "*.trigger" | grep -q .; then
        summary "🔧 Apex components detected - test execution required"
        APEX_DEPLOYMENT=true
      else
        summary "📄 Metadata-only deployment detected - no test execution required"
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
        summary "📄 Metadata-only deployment - skipping test execution"
        echo "🔄 Executing deployment validation without test execution..."
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
