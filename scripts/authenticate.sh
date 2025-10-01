#!/bin/bash
# ==============================================================================
# Salesforce Authentication Script
# ==============================================================================
# Establishes secure authenticated session with Salesforce sandbox environment
# for deployment validation operations.
#
# Security Measures:
#   - Validates required authentication credentials
#   - Uses temporary files for credential handling
#   - Implements secure cleanup of sensitive data
#   - Sets authenticated org as default for subsequent operations
#
# Environment Requirements:
#   - SF_AUTH_URL: Salesforce authentication URL (stored as GitHub secret)
# ==============================================================================

set -euo pipefail

echo "🔐 Establishing Salesforce environment authentication..."

# Validate required environment variable
if [ -z "${SF_AUTH_URL:-}" ]; then
  echo "❌ Error: SF_AUTH_URL environment variable is not configured"
  echo "💡 Ensure SF_AUTH_URL secret is properly configured in repository settings"
  exit 1
fi

# Write authentication URL to temporary file for security
AUTH_FILE="/tmp/authFile.txt"
echo "$SF_AUTH_URL" > "$AUTH_FILE"

# Authenticate using SFDX URL and configure as default org
if sf org login sfdx-url \
  --sfdx-url-file "$AUTH_FILE" \
  --alias sandbox \
  --set-default >/dev/null 2>&1; then

  echo "✅ Authentication successful - sandbox environment ready"
  # Secure cleanup of temporary authentication file
  rm -f "$AUTH_FILE"
else
  echo "❌ Authentication failed - check credentials and network connectivity"
  rm -f "$AUTH_FILE"
  exit 1
fi
