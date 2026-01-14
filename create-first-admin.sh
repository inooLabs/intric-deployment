#!/usr/bin/env bash
set -e

# =============================================================================
# Intric First User Setup Script
# Creates a tenant and the first admin user in your Intric deployment
# =============================================================================

# =============================================================================
# Functions
# =============================================================================

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

print_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Creates a tenant and the first admin user in Intric.

OPTIONS:
    --overrideFile FILE         Path to values-override.yaml (required)
    --zitadelPat PAT           Zitadel Personal Access Token (required)
    --zitadelHost HOST         Zitadel host (e.g., login.example.com)
                               If not provided, will be extracted from override file
    --organizationName NAME    Organization/Tenant name (optional, will prompt)
    --userEmail EMAIL          Email for the first admin user (optional, will prompt)
    -h, --help                 Show this help message

ENVIRONMENT VARIABLES:
    ZITADEL_PAT               Alternative way to provide Zitadel PAT
    ORGANIZATION_NAME         Alternative way to provide organization name
    USER_EMAIL                Alternative way to provide user email

EXAMPLES:
    # Basic usage (will prompt for org name and email)
    $0 --overrideFile helm/intric/values-override.yaml \\
       --zitadelPat "your-zitadel-pat"
    
    # Non-interactive mode
    $0 --overrideFile helm/intric/values-override.yaml \\
       --zitadelPat "your-pat" \\
       --organizationName "My Company" \\
       --userEmail "admin@example.com"
    
    # Using environment variables and custom zitadel host
    export ZITADEL_PAT="your-pat"
    $0 --overrideFile helm/intric/values-override.yaml \\
       --zitadelHost "login.intric.ai"

EOF
}

# =============================================================================
# Parse Arguments
# =============================================================================

OVERRIDE_FILE=""
ZITADEL_PAT=""
ZITADEL_HOST=""
ORGANIZATION_NAME=""
USER_EMAIL=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --overrideFile)
            OVERRIDE_FILE="$2"
            shift 2
            ;;
        --zitadelPat)
            ZITADEL_PAT="$2"
            shift 2
            ;;
        --zitadelHost)
            ZITADEL_HOST="$2"
            shift 2
            ;;
        --organizationName)
            ORGANIZATION_NAME="$2"
            shift 2
            ;;
        --userEmail)
            USER_EMAIL="$2"
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
# Validate Required Inputs
# =============================================================================

if [ -z "$OVERRIDE_FILE" ]; then
    error "Override file is required. Provide it via --overrideFile option."
fi

if [ ! -f "$OVERRIDE_FILE" ]; then
    error "Override file not found: $OVERRIDE_FILE"
fi

if [ -z "$ZITADEL_PAT" ]; then
    error "Zitadel PAT is required. Provide it via --zitadelPat option or ZITADEL_PAT environment variable."
fi

info "Using override file: $OVERRIDE_FILE"

# =============================================================================
# Extract Configuration from Override File
# =============================================================================

info "Extracting configuration from override file..."

# Extract backend URL from ingress.backendHost
BACKEND_HOST=$(grep -A 10 "^ingress:" "$OVERRIDE_FILE" | grep "backendHost:" | head -1 | sed 's/.*backendHost: *//' | tr -d '"' | tr -d ' ')

if [ -z "$BACKEND_HOST" ]; then
    error "Could not extract backend host from $OVERRIDE_FILE"
fi

BACKEND_URL="https://${BACKEND_HOST}"
success "Backend URL: $BACKEND_URL"

# Extract or use provided Zitadel URL
if [ -n "$ZITADEL_HOST" ]; then
    # Use the provided zitadel host
    ZITADEL_URL="https://${ZITADEL_HOST}"
    success "Using provided Zitadel host: $ZITADEL_HOST"
else
    # Extract Zitadel URL from intricBackendApiServer.zitadelEndpoint
    ZITADEL_URL=$(grep "zitadelEndpoint:" "$OVERRIDE_FILE" | head -1 | sed 's/.*zitadelEndpoint: *//' | tr -d '"' | tr -d ' ')

    if [ -z "$ZITADEL_URL" ]; then
        error "Could not extract zitadelEndpoint from $OVERRIDE_FILE. Please provide it via --zitadelHost option."
    fi
    
    success "Extracted Zitadel URL from override file"
fi

success "Zitadel URL: $ZITADEL_URL"

# Extract Super API Key
SUPER_API_KEY=$(grep "intricSuperApiKey:" "$OVERRIDE_FILE" | head -1 | sed 's/.*intricSuperApiKey: *//' | sed 's/^"\(.*\)"$/\1/' | tr -d ' ')

if [ -z "$SUPER_API_KEY" ]; then
    error "Could not extract intricSuperApiKey from $OVERRIDE_FILE"
fi

success "Super API Key found"

# =============================================================================
# Get Zitadel Organization Information
# =============================================================================

info "Fetching Zitadel organization information..."

ME_RESPONSE=$(curl -s -X GET "${ZITADEL_URL}/auth/v1/users/me" \
    -H "Authorization: Bearer ${ZITADEL_PAT}" \
    -H "Content-Type: application/json")

ZITADEL_ORG_ID=$(echo "$ME_RESPONSE" | jq -r '.user.details.resourceOwner' 2>/dev/null)

if [ -z "$ZITADEL_ORG_ID" ] || [ "$ZITADEL_ORG_ID" = "null" ]; then
    error "Failed to get Zitadel organization ID. Response: $ME_RESPONSE"
fi

success "Zitadel Organization ID: $ZITADEL_ORG_ID"

# =============================================================================
# Collect remaining inputs (prompt if not provided)
# =============================================================================

if [ -z "$ORGANIZATION_NAME" ]; then
    read -r -p "Organization Name: " ORGANIZATION_NAME
fi

if [ -z "$USER_EMAIL" ]; then
    read -r -p "Admin User Email: " USER_EMAIL
fi

# =============================================================================
# Validate all inputs
# =============================================================================

if [ -z "$ORGANIZATION_NAME" ]; then
    error "Organization Name is required"
fi

if [ -z "$USER_EMAIL" ]; then
    error "User Email is required"
fi

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "Intric First User Setup"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "  Backend URL: $BACKEND_URL"
echo "  Organization: $ORGANIZATION_NAME"
echo "  Zitadel Org ID: $ZITADEL_ORG_ID"
echo "  Admin Email: $USER_EMAIL"
echo ""

# =============================================================================
# Step 1: Create Tenant
# =============================================================================

info "Creating tenant '$ORGANIZATION_NAME'..."

CREATE_TENANT_RESPONSE=$(curl -ksS -w "\n%{http_code}" -X POST "$BACKEND_URL/api/v1/sysadmin/tenants/" \
    -H "Content-Type: application/json" \
    -H "api-key: $SUPER_API_KEY" \
    -d "{
        \"name\": \"$ORGANIZATION_NAME\",
        \"zitadel_org_id\": \"$ZITADEL_ORG_ID\"
    }")

HTTP_CODE=$(echo "$CREATE_TENANT_RESPONSE" | tail -n 1)
RESPONSE_BODY=$(echo "$CREATE_TENANT_RESPONSE" | sed '$d')

if [[ ! "$HTTP_CODE" =~ ^2[0-9]{2}$ ]]; then
    error "Failed to create tenant (HTTP $HTTP_CODE). Response: $RESPONSE_BODY"
fi

TENANT_ID=$(echo "$RESPONSE_BODY" | jq -r '.id' 2>/dev/null)

if [ -z "$TENANT_ID" ] || [ "$TENANT_ID" = "null" ]; then
    error "Failed to extract tenant ID from response: $RESPONSE_BODY"
fi

success "Tenant created successfully (ID: $TENANT_ID)"

# =============================================================================
# Step 2: Get Predefined Roles
# =============================================================================

info "Fetching predefined roles..."

ROLES_RESPONSE=$(curl -ksS -w "\n%{http_code}" -X GET "$BACKEND_URL/api/v1/sysadmin/predefined-roles/" \
    -H "Accept: application/json" \
    -H "api-key: $SUPER_API_KEY")

HTTP_CODE=$(echo "$ROLES_RESPONSE" | tail -n 1)
RESPONSE_BODY=$(echo "$ROLES_RESPONSE" | sed '$d')

if [[ ! "$HTTP_CODE" =~ ^2[0-9]{2}$ ]]; then
    error "Failed to fetch predefined roles (HTTP $HTTP_CODE). Response: $RESPONSE_BODY"
fi

# Find the Admin role ID
ADMIN_ROLE_ID=$(echo "$RESPONSE_BODY" | jq -r '.[] | select(.name == "Admin") | .id' 2>/dev/null)

if [ -z "$ADMIN_ROLE_ID" ] || [ "$ADMIN_ROLE_ID" = "null" ]; then
    error "Could not find Admin role in predefined roles. Response: $RESPONSE_BODY"
fi

success "Found Admin role (ID: $ADMIN_ROLE_ID)"

# =============================================================================
# Step 3: Create Admin User
# =============================================================================

info "Creating admin user '$USER_EMAIL'..."

CREATE_USER_RESPONSE=$(curl -ksS -w "\n%{http_code}" -X POST "$BACKEND_URL/api/v1/sysadmin/users/" \
    -H "Content-Type: application/json" \
    -H "api-key: $SUPER_API_KEY" \
    -d "{
        \"email\": \"$USER_EMAIL\",
        \"predefined_roles\": [{\"id\": \"$ADMIN_ROLE_ID\"}],
        \"tenant_id\": \"$TENANT_ID\",
        \"is_superuser\": true
    }")

HTTP_CODE=$(echo "$CREATE_USER_RESPONSE" | tail -n 1)
RESPONSE_BODY=$(echo "$CREATE_USER_RESPONSE" | sed '$d')

if [[ ! "$HTTP_CODE" =~ ^2[0-9]{2}$ ]]; then
    error "Failed to create user (HTTP $HTTP_CODE). Response: $RESPONSE_BODY"
fi

USER_ID=$(echo "$RESPONSE_BODY" | jq -r '.id' 2>/dev/null)

if [ -z "$USER_ID" ] || [ "$USER_ID" = "null" ]; then
    # Some APIs might not return an ID, so just check for success
    success "Admin user created successfully"
else
    success "Admin user created successfully (ID: $USER_ID)"
fi

# =============================================================================
# Display Results
# =============================================================================

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "✅ Setup Complete!"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "  Organization: $ORGANIZATION_NAME"
echo "  Tenant ID: $TENANT_ID"
echo "  Admin Email: $USER_EMAIL"
echo "  Admin Role ID: $ADMIN_ROLE_ID"
echo "  Superuser: Yes"
echo ""
echo "════════════════════════════════════════════════════════════════"
echo "Next Steps:"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "1. The user should receive a Zitadel invitation email at:"
echo "   $USER_EMAIL"
echo ""
echo "2. Have the user click the link in the email to set their password"
echo ""
echo "3. The user can then login at your frontend URL with:"
echo "   - Email: $USER_EMAIL"
echo "   - Password: (set via Zitadel invitation)"
echo ""
echo "4. As a superuser, this user has full administrative access"
echo ""

