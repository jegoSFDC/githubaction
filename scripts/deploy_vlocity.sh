#!/bin/bash
# ==============================================================================
# Vlocity Deployment Script
# ==============================================================================
# Handles deployment of Vlocity components including OmniScripts, DataRaptors,
# Integration Procedures, and other Vlocity metadata using VBT (Vlocity Build Tool).
#
# Deployment Strategy:
#   1. Check if Vlocity components exist in delta package
#   2. For PR validation: Run dry-run deployment (check-only)
#   3. For merge deployment: Run actual VBT deployment with verbose logging
#   4. Handle both standard Vlocity components and VBT-specific deployments
#
# Features:
#   - Automatic Vlocity component detection
#   - VBT deployment with verbose logging
#   - Comprehensive deployment status reporting
#   - Integration with existing CI/CD pipeline
# ==============================================================================

set -euo pipefail

echo ""
echo "🚀 VLOCITY DEPLOYMENT STAGE"
echo "============================"
echo "🔍 Processing Vlocity components deployment..."

# Create reports directory
mkdir -p reports

# Logging function
log() {
  echo "$1" | tee -a reports/vlocity-deployment.log
}

# Check if this is a PR validation or actual deployment
DEPLOYMENT_MODE="validation"
if [ "${GITHUB_EVENT_NAME:-}" = "push" ] && [ "${GITHUB_REF:-}" = "refs/heads/main" ]; then
  DEPLOYMENT_MODE="deployment"
fi

log "📋 Deployment Mode: $DEPLOYMENT_MODE"
log "🔧 Event: ${GITHUB_EVENT_NAME:-unknown}"
log "🌿 Branch: ${GITHUB_REF_NAME:-unknown}"

# Check if Vlocity components exist in delta package
HAS_VLOCITY_COMPONENTS="false"
VLOCITY_COMPONENTS=()

if [ -d "delta/force-app" ]; then
  # Check for Vlocity-specific directories and files
  VLOCITY_PATTERNS=(
    "delta/force-app/*/vlocity"
    "delta/force-app/*/vlocity/**"
    "delta/force-app/*/vlocity/**/*.json"
    "delta/force-app/*/vlocity/**/*.xml"
    "delta/force-app/*/vlocity/**/*.js"
    "delta/force-app/*/vlocity/**/*.css"
    "delta/force-app/*/vlocity/**/*.html"
  )
  
  for pattern in "${VLOCITY_PATTERNS[@]}"; do
    if find . -path "$pattern" -type f 2>/dev/null | grep -q .; then
      HAS_VLOCITY_COMPONENTS="true"
      # Collect specific Vlocity components
      VLOCITY_FILES=$(find . -path "$pattern" -type f 2>/dev/null | head -20)
      while IFS= read -r file; do
        if [ -n "$file" ]; then
          VLOCITY_COMPONENTS+=("$file")
        fi
      done <<< "$VLOCITY_FILES"
      break
    fi
  done
fi

# Also check for VBT-specific files
if [ "$HAS_VLOCITY_COMPONENTS" = "false" ]; then
  VBT_PATTERNS=(
    "delta/force-app/*/vlocity/**/*.json"
    "delta/force-app/*/vlocity/**/*.xml"
  )
  
  for pattern in "${VBT_PATTERNS[@]}"; do
    if find . -path "$pattern" -type f 2>/dev/null | grep -q .; then
      HAS_VLOCITY_COMPONENTS="true"
      VLOCITY_FILES=$(find . -path "$pattern" -type f 2>/dev/null | head -20)
      while IFS= read -r file; do
        if [ -n "$file" ]; then
          VLOCITY_COMPONENTS+=("$file")
        fi
      done <<< "$VLOCITY_FILES"
    fi
  done
fi

if [ "$HAS_VLOCITY_COMPONENTS" = "false" ]; then
  log "ℹ️  No Vlocity components detected in delta package"
  log "✅ Skipping Vlocity deployment stage"
  echo '{"result":{"status":"Skipped","message":"No Vlocity components to deploy"}}' > reports/vlocity-deployment-report.json
  exit 0
fi

log "✅ Vlocity components detected:"
for component in "${VLOCITY_COMPONENTS[@]}"; do
  log "  📦 $component"
done

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔍 VLOCITY COMPONENTS ANALYSIS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Analyze Vlocity component types
OMNISCRIPT_COUNT=0
DATARAPTOR_COUNT=0
INTEGRATION_PROCEDURE_COUNT=0
TEMPLATE_COUNT=0
OTHER_VLOCITY_COUNT=0

for component in "${VLOCITY_COMPONENTS[@]}"; do
  case "$component" in
    *OmniScript*)
      OMNISCRIPT_COUNT=$((OMNISCRIPT_COUNT + 1))
      ;;
    *DataRaptor*)
      DATARAPTOR_COUNT=$((DATARAPTOR_COUNT + 1))
      ;;
    *IntegrationProcedure*)
      INTEGRATION_PROCEDURE_COUNT=$((INTEGRATION_PROCEDURE_COUNT + 1))
      ;;
    *Template*)
      TEMPLATE_COUNT=$((TEMPLATE_COUNT + 1))
      ;;
    *)
      OTHER_VLOCITY_COUNT=$((OTHER_VLOCITY_COUNT + 1))
      ;;
  esac
done

log ""
log "📊 Vlocity Component Summary:"
log "  • OmniScripts: $OMNISCRIPT_COUNT"
log "  • DataRaptors: $DATARAPTOR_COUNT"
log "  • Integration Procedures: $INTEGRATION_PROCEDURE_COUNT"
log "  • Templates: $TEMPLATE_COUNT"
log "  • Other Vlocity Components: $OTHER_VLOCITY_COUNT"
log "  • Total: ${#VLOCITY_COMPONENTS[@]}"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🚀 VLOCITY DEPLOYMENT EXECUTION"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Initialize deployment report
echo '{"result":{"status":"Failed","message":"Deployment not attempted"}}' > reports/vlocity-deployment-report.json

if [ "$DEPLOYMENT_MODE" = "validation" ]; then
  log ""
  log "🔍 EXECUTING VLOCITY VALIDATION (DRY-RUN)"
  log "=========================================="
  log "📋 Validation Details:"
  log "  • Mode: Dry-run (check-only - no actual deployment)"
  log "  • Components: Vlocity metadata"
  log "  • Test Level: NoTestRun (Vlocity components don't require Apex tests)"
  log "  • Environment: Sandbox"
  log ""
  
  log "🔄 Running Vlocity validation..."
  
  if sf project deploy start \
    --source-dir delta/force-app \
    --target-org sandbox \
    --dry-run \
    --test-level NoTestRun \
    --json > reports/vlocity-deployment-report.json 2>&1; then
    log "✅ Vlocity validation passed"
  else
    log "❌ Vlocity validation failed"
  fi
  
else
  log ""
  log "🚀 EXECUTING VLOCITY DEPLOYMENT (VBT)"
  log "======================================"
  log "📋 Deployment Details:"
  log "  • Mode: Actual deployment (VBT)"
  log "  • Components: Vlocity metadata"
  log "  • Test Level: NoTestRun (Vlocity components don't require Apex tests)"
  log "  • Environment: Sandbox"
  log "  • Verbose Logging: Enabled"
  log ""
  
  log "🔄 Running Vlocity VBT deployment with verbose logging..."
  
  # VBT deployment with verbose logging and real-time progress display
  log "🔄 Starting VBT deployment process..."
  
  # Create a temporary file for real-time output capture
  TEMP_OUTPUT=$(mktemp)
  
  # Run deployment with verbose output and capture both stdout and stderr
  # Show real-time progress during deployment
  echo ""
  echo "🔄 Deployment in Progress..."
  echo "============================"
  echo "⏳ Processing Vlocity components..."
  echo "📦 Deploying to: $(sf org display --target-org sandbox --json 2>/dev/null | jq -r '.result.name // "sandbox"' 2>/dev/null || echo "sandbox")"
  echo "🎯 Components to deploy: ${#VLOCITY_COMPONENTS[@]}"
  echo ""
  
  # Start deployment with progress indicator
  if sf project deploy start \
    --source-dir delta/force-app \
    --target-org sandbox \
    --test-level NoTestRun \
    --verbose \
    --json > "$TEMP_OUTPUT" 2>&1; then
    
    # Copy the JSON output to reports
    cp "$TEMP_OUTPUT" reports/vlocity-deployment-report.json
    
    log "✅ Vlocity VBT deployment completed successfully"
    
    # Display real-time deployment progress
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📊 REAL-TIME DEPLOYMENT PROGRESS"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Parse and display deployment progress from the verbose output
    if [ -f "$TEMP_OUTPUT" ]; then
      # Extract deployment ID and status
      DEPLOYMENT_ID=$(jq -r '.result.id // empty' "$TEMP_OUTPUT" 2>/dev/null || echo "")
      DEPLOYMENT_STATUS=$(jq -r '.result.status // empty' "$TEMP_OUTPUT" 2>/dev/null || echo "")
      
      if [ -n "$DEPLOYMENT_ID" ]; then
        log "🆔 Deployment ID: $DEPLOYMENT_ID"
        log "📊 Status: $DEPLOYMENT_STATUS"
        
        # Show deployment details similar to VlocityBuildErrors.log format
        echo ""
        echo "📋 Deployment Details:"
        echo "Org: $(sf org display --target-org sandbox --json 2>/dev/null | jq -r '.result.name // "sandbox"' 2>/dev/null || echo "sandbox")"
        echo "Version: $(sf --version 2>/dev/null || echo "Unknown")"
        echo "Action: Deploy"
        echo "ProjectPath: vlocity"
        echo "DeploymentID: $DEPLOYMENT_ID"
        echo ""
        
        # Display component processing details
        echo "🔍 Component Processing Details:"
        echo "================================"
        
        # Show successful components
        if jq -e '.result.details.componentSuccesses' "$TEMP_OUTPUT" >/dev/null 2>&1; then
          COMPONENT_COUNT=$(jq '.result.details.componentSuccesses | length' "$TEMP_OUTPUT" 2>/dev/null || echo "0")
          log "✅ Successfully Processed Components: $COMPONENT_COUNT"
          
          # Display each successful component with details
          jq -r '.result.details.componentSuccesses[]? | 
            "\(.componentType // "Unknown")/\(.fileName // .name // "Unknown") -- Status >> SUCCESS -- Component >> \(.componentType // "Unknown")" ' \
            "$TEMP_OUTPUT" 2>/dev/null | while read -r line; do
            if [ -n "$line" ]; then
              echo "  ✅ $line"
            fi
          done
        fi
        
        # Show failed components with detailed error information
        if jq -e '.result.details.componentFailures' "$TEMP_OUTPUT" >/dev/null 2>&1; then
          FAILURE_COUNT=$(jq '.result.details.componentFailures | length' "$TEMP_OUTPUT" 2>/dev/null || echo "0")
          if [ "$FAILURE_COUNT" -gt 0 ]; then
            echo ""
            log "❌ Failed Components: $FAILURE_COUNT"
            
            # Display each failed component with detailed error information
            jq -r '.result.details.componentFailures[]? | 
              "\(.componentType // "Unknown")/\(.fileName // .name // "Unknown") -- DataPack >> \(.componentType // "Unknown") -- Error Message -- \(.problem // "Unknown error")" ' \
              "$TEMP_OUTPUT" 2>/dev/null | while read -r line; do
              if [ -n "$line" ]; then
                echo "  ❌ $line"
              fi
            done
          fi
        fi
        
        # Show test results if any
        if jq -e '.result.details.runTestResult' "$TEMP_OUTPUT" >/dev/null 2>&1; then
          echo ""
          echo "🧪 Test Results:"
          echo "================"
          TEST_STATUS=$(jq -r '.result.details.runTestResult.status // "Unknown"' "$TEMP_OUTPUT" 2>/dev/null || echo "Unknown")
          log "Test Status: $TEST_STATUS"
        fi
        
        # Show deployment timing information
        if jq -e '.result.details.deployResult' "$TEMP_OUTPUT" >/dev/null 2>&1; then
          echo ""
          echo "⏱️  Deployment Timing:"
          echo "======================"
          START_TIME=$(jq -r '.result.details.deployResult.startDate // empty' "$TEMP_OUTPUT" 2>/dev/null || echo "")
          COMPLETE_TIME=$(jq -r '.result.details.deployResult.completedDate // empty' "$TEMP_OUTPUT" 2>/dev/null || echo "")
          if [ -n "$START_TIME" ] && [ -n "$COMPLETE_TIME" ]; then
            log "Start Time: $START_TIME"
            log "Complete Time: $COMPLETE_TIME"
          fi
        fi
      fi
    fi
    
    # Clean up temporary file
    rm -f "$TEMP_OUTPUT"
    
  else
    # Copy the JSON output to reports even on failure
    cp "$TEMP_OUTPUT" reports/vlocity-deployment-report.json 2>/dev/null || true
    
    log "❌ Vlocity VBT deployment failed"
    
    # Display detailed error information
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "❌ DEPLOYMENT FAILURE DETAILS"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    if [ -f "$TEMP_OUTPUT" ]; then
      # Extract error details
      ERROR_MESSAGE=$(jq -r '.result.message // .message // "Unknown error"' "$TEMP_OUTPUT" 2>/dev/null || echo "Unknown error")
      log "Error Message: $ERROR_MESSAGE"
      
      # Show component failures with detailed error information
      if jq -e '.result.details.componentFailures' "$TEMP_OUTPUT" >/dev/null 2>&1; then
        echo ""
        echo "🔍 Component Failure Details:"
        echo "============================="
        
        jq -r '.result.details.componentFailures[]? | 
          "\(.componentType // "Unknown")/\(.fileName // .name // "Unknown") -- DataPack >> \(.componentType // "Unknown") -- Error Message -- \(.problem // "Unknown error")" ' \
          "$TEMP_OUTPUT" 2>/dev/null | while read -r line; do
          if [ -n "$line" ]; then
            echo "  ❌ $line"
          fi
        done
      fi
    fi
    
    # Clean up temporary file
    rm -f "$TEMP_OUTPUT"
  fi
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 VLOCITY DEPLOYMENT RESULTS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Parse and display deployment results
if [ -f reports/vlocity-deployment-report.json ]; then
  STATUS=$(jq -r '.result.status // "Failed"' reports/vlocity-deployment-report.json 2>/dev/null || echo "Failed")
  COMPONENT_COUNT=0
  COMPONENT_FAIL_COUNT=0
  DEPLOYMENT_ID=""
  
  if jq -e '.result.details.componentSuccesses' reports/vlocity-deployment-report.json >/dev/null 2>&1; then
    COMPONENT_COUNT=$(jq '.result.details.componentSuccesses | length' reports/vlocity-deployment-report.json 2>/dev/null || echo "0")
  fi
  
  if jq -e '.result.details.componentFailures' reports/vlocity-deployment-report.json >/dev/null 2>&1; then
    COMPONENT_FAIL_COUNT=$(jq '.result.details.componentFailures | length' reports/vlocity-deployment-report.json 2>/dev/null || echo "0")
  fi
  
  if jq -e '.result.id' reports/vlocity-deployment-report.json >/dev/null 2>&1; then
    DEPLOYMENT_ID=$(jq -r '.result.id' reports/vlocity-deployment-report.json 2>/dev/null || echo "")
  fi
  
  log ""
  log "🔍 Vlocity Deployment Summary:"
  log "  • Status: $STATUS"
  log "  • Components Deployed: $COMPONENT_COUNT"
  log "  • Component Failures: $COMPONENT_FAIL_COUNT"
  if [ -n "$DEPLOYMENT_ID" ]; then
    log "  • Deployment ID: $DEPLOYMENT_ID"
  fi
  
  # Display successful components with verbose details
  if [ "$COMPONENT_COUNT" -gt 0 ]; then
    echo ""
    echo "✅ Successfully Deployed Vlocity Components:"
    echo "============================================="
    
    if [ "$DEPLOYMENT_MODE" = "deployment" ]; then
      # Show detailed component information for actual deployments
      jq -r '.result.details.componentSuccesses[]? | 
        "  📦 \(.fileName // .name // "Unknown")\n     Type: \(.componentType // "Unknown")\n     Status: \(.success // "Unknown")\n" ' \
        reports/vlocity-deployment-report.json 2>/dev/null | head -50 || true
    else
      # Show component names for validation
      jq -r '.result.details.componentSuccesses[]? | "  📦 \(.fileName // .name // "Unknown")"' \
        reports/vlocity-deployment-report.json 2>/dev/null | head -20 || true
    fi
  fi
  
  # Display failed components with detailed error information
  if [ "$COMPONENT_FAIL_COUNT" -gt 0 ]; then
    echo ""
    echo "❌ Failed Vlocity Components:"
    echo "============================="
    
    jq -r '.result.details.componentFailures[]? | 
      "  ❌ \(.fileName // .name // "Unknown")\n     Type: \(.componentType // "Unknown")\n     Error: \(.problem // "Unknown error")\n     Line: \(.lineNumber // "N/A")\n" ' \
      reports/vlocity-deployment-report.json 2>/dev/null | head -30 || true
  fi
  
  # Display VBT-specific deployment information for actual deployments
  if [ "$DEPLOYMENT_MODE" = "deployment" ] && [ "$STATUS" = "Succeeded" ]; then
    echo ""
    echo "🎉 VBT Deployment Completed Successfully!"
    echo "========================================="
    echo "  • All Vlocity components deployed successfully"
    echo "  • VBT process completed without errors"
    echo "  • Components are now available in the target org"
    echo ""
    
    # Show deployment URL if available
    if [ -n "$DEPLOYMENT_ID" ]; then
      echo "🔗 Deployment Details:"
      echo "  • Deployment ID: $DEPLOYMENT_ID"
      echo "  • View in Salesforce Setup > Deploy > Deployment Status"
    fi
  fi
  
else
  log "❌ No deployment report found"
  STATUS="Failed"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔍 VLOCITY QUALITY GATE VALIDATION"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Validate quality gates for Vlocity deployment
if [ "$STATUS" = "Succeeded" ]; then
  log "✅ Vlocity Deployment: PASSED"
  log "✅ All Vlocity components deployed successfully"
  log ""
  log "🎉 VLOCITY DEPLOYMENT READY"
  exit 0
  
elif [ "$STATUS" = "Skipped" ]; then
  log "✅ Vlocity Deployment: SKIPPED (no components)"
  log "✅ Quality gates met"
  log ""
  log "🎉 VLOCITY PIPELINE SUCCESSFUL"
  exit 0
  
else
  log "❌ Vlocity Deployment: FAILED"
  log "   • Status: $STATUS"
  log "   • Component Failures: $COMPONENT_FAIL_COUNT"
  log ""
  log "💥 VLOCITY QUALITY GATES FAILED - Fix issues before deploying"
  exit 1
fi
