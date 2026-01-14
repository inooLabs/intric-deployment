#!/bin/bash
set -e

# =============================================================================
# Zitadel Project Setup Script
# Creates a "production" project in Zitadel using a Personal Access Token
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OVERRIDE_FILE_IN=""
OVERRIDE_FILE_OUT=""
PROJECT_NAME="${PROJECT_NAME:-production}"
ZITADEL_HOST=""

# =============================================================================
# Functions
# =============================================================================

print_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Creates a "production" project and "Intric" application in Zitadel, then updates the configuration file.

OPTIONS:
    -p, --pat PAT                   Zitadel Personal Access Token (required)
    --overrideFileIn FILE           Input values override file (required)
    --overrideFileOut FILE          Output values override file (required)
    -z, --zitadelHost HOST          Zitadel host (e.g., login.example.com)
                                    If not provided, will be extracted from override file
    -n, --name NAME                 Project name to create (default: production)
    -h, --help                      Show this help message

ENVIRONMENT VARIABLES:
    ZITADEL_PAT            Alternative way to provide the PAT
    PROJECT_NAME           Alternative way to set project name

EXAMPLES:
    # Basic usage
    $0 --pat "your-pat" \\
       --overrideFileIn helm/intric/values-override.yaml \\
       --overrideFileOut helm/intric/values-override-updated.yaml
    
    # Using environment variable for PAT
    export ZITADEL_PAT="your-zitadel-pat-here"
    $0 --overrideFileIn values-override.yaml \\
       --overrideFileOut values-override-new.yaml
    
    # Custom project name and zitadel host
    $0 --pat "your-pat" \\
       --overrideFileIn values.yaml \\
       --overrideFileOut values-new.yaml \\
       --name "staging" \\
       --zitadelHost "login.staging.example.com"

EOF
}

error() {
    echo "❌ Error: $1" >&2
    exit 1
}

info() {
    echo "ℹ️  $1"
}

success() {
    echo "✅ $1"
}

# =============================================================================
# Parse Arguments
# =============================================================================

while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--pat)
            ZITADEL_PAT="$2"
            shift 2
            ;;
        --overrideFileIn)
            OVERRIDE_FILE_IN="$2"
            shift 2
            ;;
        --overrideFileOut)
            OVERRIDE_FILE_OUT="$2"
            shift 2
            ;;
        -z|--zitadelHost)
            ZITADEL_HOST="$2"
            shift 2
            ;;
        -n|--name)
            PROJECT_NAME="$2"
            shift 2
            ;;
        -h|--help)
            print_usage
            exit 0
            ;;
        *)
            error "Unknown option: $1. Use --help for usage information."
            ;;
    esac
done

# =============================================================================
# Validate Inputs
# =============================================================================

if [ -z "$ZITADEL_PAT" ]; then
    error "Zitadel PAT is required. Provide it via --pat option or ZITADEL_PAT environment variable."
fi

if [ -z "$OVERRIDE_FILE_IN" ]; then
    error "Input override file is required. Provide it via --overrideFileIn option."
fi

if [ -z "$OVERRIDE_FILE_OUT" ]; then
    error "Output override file is required. Provide it via --overrideFileOut option."
fi

if [ ! -f "$OVERRIDE_FILE_IN" ]; then
    error "Input override file not found: $OVERRIDE_FILE_IN"
fi

info "Input override file: $OVERRIDE_FILE_IN"
info "Output override file: $OVERRIDE_FILE_OUT"

# =============================================================================
# Extract Zitadel URL from Override File or Argument
# =============================================================================

if [ -n "$ZITADEL_HOST" ]; then
    # Use the provided zitadel host
    ZITADEL_DOMAIN="$ZITADEL_HOST"
    success "Using provided Zitadel host: $ZITADEL_DOMAIN"
else
    # Extract from override file
    info "Extracting Zitadel URL from input override file..."

    # Try to extract from zitadel.externalDomain
    ZITADEL_DOMAIN=$(grep -A 5 "^zitadel:" "$OVERRIDE_FILE_IN" | grep "externalDomain:" | head -1 | sed 's/.*externalDomain: *//' | tr -d '"' | tr -d ' ')

    # If not found, try ingress.zitadelHost
    if [ -z "$ZITADEL_DOMAIN" ]; then
        ZITADEL_DOMAIN=$(grep -A 10 "^ingress:" "$OVERRIDE_FILE_IN" | grep "zitadelHost:" | head -1 | sed 's/.*zitadelHost: *//' | tr -d '"' | tr -d ' ')
    fi

    if [ -z "$ZITADEL_DOMAIN" ]; then
        error "Could not extract Zitadel domain from $OVERRIDE_FILE_IN. Please provide it via --zitadelHost option."
    fi
    
    success "Extracted Zitadel domain from override file"
fi

ZITADEL_URL="https://${ZITADEL_DOMAIN}"
success "Zitadel URL: $ZITADEL_URL"

FRONTEND_HOST=$(grep -A 10 "^ingress:" "$OVERRIDE_FILE_IN" | grep "frontendHost:" | head -1 | sed 's/.*frontendHost: *//' | tr -d '"' | tr -d ' ')

if [ -z "$FRONTEND_HOST" ]; then
    error "Could not extract frontend host from $OVERRIDE_FILE_IN. Please check the file format."
fi

FRONTEND_URL="https://${FRONTEND_HOST}"
success "Frontend URL: $FRONTEND_URL"

# =============================================================================
# Verify PAT
# =============================================================================

info "Verifying PAT..."

VERIFY_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "${ZITADEL_URL}/management/v1/projects/_search" \
    -H "Authorization: Bearer ${ZITADEL_PAT}" \
    -H "Content-Type: application/json" \
    -d '{}')

HTTP_CODE=$(echo "$VERIFY_RESPONSE" | tail -n 1)
RESPONSE_BODY=$(echo "$VERIFY_RESPONSE" | sed '$d')

if [ "$HTTP_CODE" != "200" ]; then
    error "PAT verification failed (HTTP $HTTP_CODE). Response: $RESPONSE_BODY"
fi

success "PAT verified successfully"

# =============================================================================
# Check if Project Already Exists
# =============================================================================

info "Checking if project '$PROJECT_NAME' already exists..."

EXISTING_PROJECT=$(curl -s -X POST "${ZITADEL_URL}/management/v1/projects/_search" \
    -H "Authorization: Bearer ${ZITADEL_PAT}" \
    -H "Content-Type: application/json" \
    -d '{}' | \
    jq -r ".result[] | select(.name == \"$PROJECT_NAME\") | .id" 2>/dev/null || echo "")

if [ -n "$EXISTING_PROJECT" ]; then
    success "Project '$PROJECT_NAME' already exists (ID: $EXISTING_PROJECT)"
    PROJECT_ID="$EXISTING_PROJECT"
    
    # Check if application already exists
    info "Checking if 'Intric' application already exists..."
    
    EXISTING_APP=$(curl -s -X POST "${ZITADEL_URL}/management/v1/projects/${PROJECT_ID}/apps/_search" \
        -H "Authorization: Bearer ${ZITADEL_PAT}" \
        -H "Content-Type: application/json" \
        -d '{}' | \
        jq -r ".result[] | select(.name == \"Intric\") | .id" 2>/dev/null || echo "")
    
    if [ -n "$EXISTING_APP" ]; then
        success "Application 'Intric' already exists (ID: $EXISTING_APP)"
        APP_ID="$EXISTING_APP"
        
        # Get the client ID for the existing app
        APP_DETAILS=$(curl -s -X GET "${ZITADEL_URL}/management/v1/projects/${PROJECT_ID}/apps/${EXISTING_APP}" \
            -H "Authorization: Bearer ${ZITADEL_PAT}" \
            -H "Content-Type: application/json")
        
        CLIENT_ID=$(echo "$APP_DETAILS" | jq -r '.app.oidcConfig.clientId' 2>/dev/null)
        
        if [ -z "$CLIENT_ID" ] || [ "$CLIENT_ID" = "null" ]; then
            error "Failed to get client ID for existing application. Response: $APP_DETAILS"
        fi
        
        success "Retrieved client ID: $CLIENT_ID"
        
        # Skip to creating output file
        SKIP_CREATION=true
    else
        # Continue to create application if it doesn't exist
        info "Application 'Intric' not found, will create it..."
        SKIP_CREATION=false
    fi
else
    # Project doesn't exist, will be created below
    PROJECT_ID=""
    SKIP_CREATION=false
fi

# =============================================================================
# Create Project (if needed)
# =============================================================================

if [ "$SKIP_CREATION" = "false" ]; then
    # Only exit early if both project AND application exist (handled above)
    if [ -n "$PROJECT_ID" ] && [ -z "$EXISTING_APP" ]; then
        # Project exists but app doesn't, continue to create app
        :
    elif [ -z "$PROJECT_ID" ]; then
        # =============================================================================
        # Create Project
        # =============================================================================

        info "Creating project '$PROJECT_NAME'..."

        CREATE_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "${ZITADEL_URL}/management/v1/projects" \
            -H "Authorization: Bearer ${ZITADEL_PAT}" \
            -H "Content-Type: application/json" \
            -d "{
                \"name\": \"$PROJECT_NAME\",
                \"projectRoleAssertion\": true,
                \"projectRoleCheck\": false,
                \"hasProjectCheck\": true,
                \"privateLabelingSetting\": \"PRIVATE_LABELING_SETTING_ENFORCE_PROJECT_RESOURCE_OWNER_POLICY\"
            }")

        HTTP_CODE=$(echo "$CREATE_RESPONSE" | tail -n 1)
        RESPONSE_BODY=$(echo "$CREATE_RESPONSE" | sed '$d')

        if [ "$HTTP_CODE" != "200" ] && [ "$HTTP_CODE" != "201" ]; then
            error "Failed to create project (HTTP $HTTP_CODE). Response: $RESPONSE_BODY"
        fi

        PROJECT_ID=$(echo "$RESPONSE_BODY" | jq -r '.id' 2>/dev/null)

        if [ -z "$PROJECT_ID" ] || [ "$PROJECT_ID" = "null" ]; then
            error "Failed to extract project ID from response: $RESPONSE_BODY"
        fi

        success "Project created successfully! (ID: $PROJECT_ID)"
    fi

    # =============================================================================
    # Create Web Application
    # =============================================================================

    info "Creating 'Intric' web application..."

    APP_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "${ZITADEL_URL}/management/v1/projects/${PROJECT_ID}/apps/oidc" \
        -H "Authorization: Bearer ${ZITADEL_PAT}" \
        -H "Content-Type: application/json" \
        -d "{
            \"name\": \"Intric\",
            \"redirectUris\": [
                \"${FRONTEND_URL}/login/callback\"
            ],
            \"postLogoutRedirectUris\": [
                \"${FRONTEND_URL}/logout\"
            ],
            \"responseTypes\": [
                \"OIDC_RESPONSE_TYPE_CODE\"
            ],
            \"grantTypes\": [
                \"OIDC_GRANT_TYPE_AUTHORIZATION_CODE\"
            ],
            \"appType\": \"OIDC_APP_TYPE_WEB\",
            \"authMethodType\": \"OIDC_AUTH_METHOD_TYPE_NONE\",
            \"version\": \"OIDC_VERSION_1_0\",
            \"devMode\": false,
            \"accessTokenType\": \"OIDC_TOKEN_TYPE_BEARER\",
            \"idTokenRoleAssertion\": true,
            \"idTokenUserinfoAssertion\": true,
            \"clockSkew\": \"0s\",
            \"additionalOrigins\": []
        }")

    HTTP_CODE=$(echo "$APP_RESPONSE" | tail -n 1)
    RESPONSE_BODY=$(echo "$APP_RESPONSE" | sed '$d')

    if [ "$HTTP_CODE" != "200" ] && [ "$HTTP_CODE" != "201" ]; then
        error "Failed to create application (HTTP $HTTP_CODE). Response: $RESPONSE_BODY"
    fi

    APP_ID=$(echo "$RESPONSE_BODY" | jq -r '.appId' 2>/dev/null)
    CLIENT_ID=$(echo "$RESPONSE_BODY" | jq -r '.clientId' 2>/dev/null)

    if [ -z "$APP_ID" ] || [ "$APP_ID" = "null" ]; then
        error "Failed to extract application ID from response: $RESPONSE_BODY"
    fi

    success "Application created successfully!"
fi

# =============================================================================
# Update Output File
# =============================================================================

info "Creating output override file with updated configuration..."

# Use sed to update the values
# This is a bit tricky because we need to preserve indentation and structure
# We'll update the intricBackendApiServer section

# Read through the file and update the zitadel values
awk -v zitadel_endpoint="$ZITADEL_URL" \
    -v project_id="$PROJECT_ID" \
    -v client_id="$CLIENT_ID" \
    -v pat="$ZITADEL_PAT" '
BEGIN { in_backend_section = 0 }
/^intricBackendApiServer:/ { in_backend_section = 1 }
/^[a-zA-Z]/ && !/^intricBackendApiServer:/ && in_backend_section { in_backend_section = 0 }

in_backend_section && /zitadelEndpoint:/ {
    print "  zitadelEndpoint: " zitadel_endpoint
    next
}
in_backend_section && /zitadelOpenidConfigEndpoint:/ {
    print "  zitadelOpenidConfigEndpoint: " zitadel_endpoint "/.well-known/openid-configuration"
    next
}
in_backend_section && /zitadelProjectClientId:/ {
    print "  zitadelProjectClientId: \"" client_id "\""
    next
}
in_backend_section && /zitadelProjectId:/ {
    print "  zitadelProjectId: \"" project_id "\""
    next
}
in_backend_section && /zitadelKeyEndpoint:/ {
    print "  zitadelKeyEndpoint: " zitadel_endpoint "/oauth/v2/keys"
    next
}
in_backend_section && /zitadelAudience:/ {
    print "  zitadelAudience: \"" client_id "\""
    next
}
in_backend_section && /zitadelAccessToken:/ {
    print "  zitadelAccessToken: " pat
    next
}
{ print }
' "$OVERRIDE_FILE_IN" > "$OVERRIDE_FILE_OUT"

success "Created output override file: $OVERRIDE_FILE_OUT"

# =============================================================================
# Display Results
# =============================================================================

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "✅ Setup Successful"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "  Project Name: $PROJECT_NAME"
echo "  Project ID: $PROJECT_ID"
echo ""
echo "  Application Name: Intric"
echo "  Application ID: $APP_ID"
echo "  Client ID: $CLIENT_ID"
echo ""
echo "  Auth Method: PKCE (Public Client)"
echo "  Redirect URI: ${FRONTEND_URL}/login/callback"
echo "  Post Logout URI: ${FRONTEND_URL}/logout"
echo ""
echo "  Console URL: ${ZITADEL_URL}/ui/console/projects/${PROJECT_ID}/apps/${APP_ID}"
echo ""
echo "  📄 Input override file: $OVERRIDE_FILE_IN"
echo "  ✅ Output override file created: $OVERRIDE_FILE_OUT"
echo ""
