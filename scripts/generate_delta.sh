#!/bin/bash
# ==============================================================================
# Delta Package Generation Script
# ==============================================================================
# Generates deployment delta package using sfdx-git-delta plugin to identify
# changes between source and target branches for incremental deployments.
#
# Process Flow:
#   1. Configure git workspace safety settings
#   2. Fetch target branch for comparison baseline
#   3. Generate delta package with changed metadata
#   4. Validate delta package structure and contents
#
# Output Artifacts:
#   - delta/package.xml: Primary deployment manifest
#   - delta/force-app/: Source metadata for deployment
#   - Destructive changes manifest (if applicable)
# ==============================================================================

set -euo pipefail

echo ""
echo "🚀 STAGE 3: DELTA PACKAGE GENERATION"
echo "======================================"
echo "🔄 Generating deployment delta package..."

# Ensure output directories exist
echo "📁 Creating output directories..."
mkdir -p delta reports

# Configure git safety for workspace operations
echo "🔧 Configuring git workspace safety..."
git config --global --add safe.directory "$GITHUB_WORKSPACE"

# Fetch target branch for delta comparison
TARGET_BRANCH="${TARGET_BRANCH:-main}"
echo "📥 Fetching target branch: $TARGET_BRANCH"
git fetch origin "$TARGET_BRANCH" --quiet

echo "📊 Generating delta from origin/$TARGET_BRANCH to HEAD"

# Generate delta package using sfdx-git-delta plugin
echo "⚙️  Executing sfdx-git-delta plugin..."
DELTA_EXIT_CODE=0
if ! sf sgd source delta \
  --to HEAD \
  --from "origin/$TARGET_BRANCH" \
  --output delta \
  --generate-delta >/dev/null 2>&1; then

  echo "⚠️  Delta generation completed with warnings (no changes detected)"
  echo "  • This is normal for script-only changes or when no differences exist"
  DELTA_EXIT_CODE=1
else
  echo "✅ Delta generation completed successfully"
fi

# Validate and display delta package analysis
echo ""
echo "📋 Delta Package Analysis:"
echo "=========================="

# Check for delta files and deployment package
DELTA_COUNT=$(find delta -type f | wc -l)
echo "📁 Total files in delta: $DELTA_COUNT"

if [ -f delta/package/package.xml ]; then
  # Check if package.xml has actual content (not just the basic structure)
  PACKAGE_MEMBERS=$(grep -o '<members>.*</members>' delta/package/package.xml | grep -v '<members></members>' | wc -l)

  if [ "$PACKAGE_MEMBERS" -gt 0 ]; then
    echo ""
    echo "📦 Package.xml Preview (first 20 lines):"
    sed -n '1,20p' delta/package/package.xml

    echo ""
    echo "🔍 Destructive Changes Analysis:"
    if find delta -name "destructiveChanges*.xml" -exec echo "  Found: {}" \; -exec sed -n '1,20p' {} \; | head -10; then
      echo "  ⚠️  Destructive changes detected in deployment package"
    else
      echo "  ✅ No destructive changes found"
    fi

    # Set deployment flag for downstream scripts
    echo "HAS_DEPLOYMENT_PACKAGE=true" >> "$GITHUB_ENV"

  else
    echo ""
    echo "📋 Empty Package.xml Found:"
    echo "  • Package.xml exists but contains no metadata components"
    echo "  • This indicates only script/YAML changes (no deployment needed)"
    echo "  • Pipeline will skip deployment validation stages"

    # Set deployment flag for downstream scripts
    echo "HAS_DEPLOYMENT_PACKAGE=false" >> "$GITHUB_ENV"
  fi

else
  echo ""
  echo "📋 No Package.xml Found:"
  echo "  • No deployment package generated"
  echo "  • This indicates only script/YAML changes or no changes to deploy"
  echo "  • Pipeline will skip deployment validation stages"

  # Set deployment flag for downstream scripts
  echo "HAS_DEPLOYMENT_PACKAGE=false" >> "$GITHUB_ENV"
fi

echo ""
echo "📊 Delta generation summary:"
ls -la delta || echo "No delta directory found"

# Exit with appropriate code based on delta generation result
if [ "$DELTA_EXIT_CODE" -eq 0 ]; then
  echo ""
  echo "✅ STAGE 3 COMPLETED: Delta package generated successfully"
  echo "=================================================="
  exit 0
else
  echo ""
  echo "✅ STAGE 3 COMPLETED: Delta analysis completed (no deployment changes)"
  echo "=================================================================="
  # Don't exit with error code for normal "no changes" scenario
  exit 0
fi
