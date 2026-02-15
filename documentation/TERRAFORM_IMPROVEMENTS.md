# Terraform Code Improvements - Preventing Deployment Issues

This document outlines improvements to prevent the three main issues encountered during initial deployment.

---

## Issue 1: RBAC Propagation Delay

### Problem
Azure RBAC role assignments take 2-5 minutes to propagate, causing 403 errors.

### Solution 1: Add Explicit Wait Time (Recommended)

Add a `time_sleep` resource after role assignments:

```hcl
# In modules/key-vault/main.tf or terraform/environments/dev/main.tf

resource "time_sleep" "wait_for_rbac_propagation" {
  depends_on = [
    azurerm_role_assignment.deployer,
    module.container_app.azurerm_role_assignment.acr_pull,
    module.container_app.azurerm_role_assignment.keyvault_secrets_user
  ]

  create_duration = "120s"  # Wait 2 minutes for RBAC propagation
}

# Make dependent resources wait for RBAC
resource "azurerm_container_app" "this" {
  # ... existing config ...

  depends_on = [
    time_sleep.wait_for_rbac_propagation
  ]
}
```

**Add to `terraform/environments/dev/versions.tf`:**
```hcl
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9"
    }
  }
}
```

### Solution 2: Retry Logic with `local-exec`

```hcl
resource "null_resource" "wait_for_storage_rbac" {
  depends_on = [azurerm_role_assignment.storage_contributor]

  provisioner "local-exec" {
    command = <<-EOT
      echo "Waiting for RBAC propagation..."
      sleep 60

      # Verify access with retries
      for i in {1..5}; do
        if az storage container list --account-name ${var.storage_account_name} --auth-mode login &>/dev/null; then
          echo "RBAC propagated successfully"
          exit 0
        fi
        echo "Retry $i/5: RBAC not yet propagated, waiting 30s..."
        sleep 30
      done

      echo "WARNING: RBAC may not be fully propagated, but continuing..."
      exit 0
    EOT
  }
}
```

### Solution 3: Use Terraform Data Source Polling

```hcl
# Poll until role assignment is visible
data "azurerm_role_assignment" "verify_acr_pull" {
  depends_on = [azurerm_role_assignment.acr_pull]

  scope                = var.container_registry_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_container_app.this.identity[0].principal_id
}

resource "time_sleep" "wait_after_verification" {
  depends_on = [data.azurerm_role_assignment.verify_acr_pull]

  create_duration = "60s"  # Additional buffer after verification
}
```

---

## Issue 2: Provider Registration

### Solution 1: Auto-Register Providers (Recommended)

**Create a new file: `terraform/environments/dev/providers-setup.tf`**

```hcl
#------------------------------------------------------------------------------
# Azure Resource Provider Registration
#------------------------------------------------------------------------------
# Ensures all required providers are registered before infrastructure deployment
# Prevents "MissingSubscriptionRegistration" errors during apply
#------------------------------------------------------------------------------

resource "azurerm_resource_provider_registration" "container_apps" {
  name = "Microsoft.App"

  lifecycle {
    # Don't fail if already registered
    ignore_changes = [name]
  }
}

resource "azurerm_resource_provider_registration" "container_registry" {
  name = "Microsoft.ContainerRegistry"
}

resource "azurerm_resource_provider_registration" "key_vault" {
  name = "Microsoft.KeyVault"
}

resource "azurerm_resource_provider_registration" "operational_insights" {
  name = "Microsoft.OperationalInsights"
}

resource "azurerm_resource_provider_registration" "insights" {
  name = "Microsoft.Insights"
}

resource "azurerm_resource_provider_registration" "storage" {
  name = "Microsoft.Storage"
}

# Wait for all providers to register
resource "time_sleep" "wait_for_providers" {
  depends_on = [
    azurerm_resource_provider_registration.container_apps,
    azurerm_resource_provider_registration.container_registry,
    azurerm_resource_provider_registration.key_vault,
    azurerm_resource_provider_registration.operational_insights,
    azurerm_resource_provider_registration.insights,
    azurerm_resource_provider_registration.storage,
  ]

  create_duration = "60s"  # Wait 1 minute for registration to complete
}

# Make resource group wait for provider registration
resource "azurerm_resource_group" "this" {
  depends_on = [time_sleep.wait_for_providers]

  # ... rest of config
}
```

### Solution 2: Pre-flight Check Script

**Create: `terraform/scripts/preflight-check.sh`**

```bash
#!/bin/bash
set -e

echo "Running pre-flight checks..."

# Check Azure CLI authentication
if ! az account show &>/dev/null; then
  echo "❌ Not logged in to Azure. Run 'az login'"
  exit 1
fi

echo "✅ Azure CLI authenticated"

# Register required providers
PROVIDERS=(
  "Microsoft.App"
  "Microsoft.ContainerRegistry"
  "Microsoft.KeyVault"
  "Microsoft.OperationalInsights"
  "Microsoft.Insights"
  "Microsoft.Storage"
)

for PROVIDER in "${PROVIDERS[@]}"; do
  echo "Checking provider: $PROVIDER"

  STATE=$(az provider show --namespace "$PROVIDER" --query registrationState -o tsv)

  if [ "$STATE" != "Registered" ]; then
    echo "  → Registering $PROVIDER..."
    az provider register --namespace "$PROVIDER" --wait
  else
    echo "  ✅ $PROVIDER already registered"
  fi
done

echo ""
echo "✅ All pre-flight checks passed!"
echo "You can now run: terraform init && terraform apply"
```

**Usage:**
```bash
chmod +x terraform/scripts/preflight-check.sh
./terraform/scripts/preflight-check.sh
terraform apply
```

### Solution 3: Makefile with Prerequisites

**Create: `terraform/environments/dev/Makefile`**

```makefile
.PHONY: preflight init plan apply deploy destroy

# Pre-flight checks before any Terraform operation
preflight:
	@echo "Running pre-flight checks..."
	@../../scripts/preflight-check.sh

# Initialize Terraform (with preflight)
init: preflight
	terraform init -backend-config=backend.hcl

# Plan infrastructure changes
plan: init
	terraform plan -out=tfplan

# Apply infrastructure changes
apply: plan
	terraform apply tfplan

# Full deployment (one command)
deploy: preflight init plan apply

# Destroy infrastructure
destroy: init
	terraform destroy
```

**Usage:**
```bash
make deploy    # Runs preflight + init + plan + apply
make plan      # Just planning
```

---

## Issue 3: Container Registry Circular Dependency

### Solution 1: User-Assigned Managed Identity (Best Practice)

Create the managed identity separately, then reference it in Container App:

**Create: `terraform/modules/managed-identity/main.tf`**

```hcl
resource "azurerm_user_assigned_identity" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}

# Grant ACR Pull immediately after identity creation
resource "azurerm_role_assignment" "acr_pull" {
  count = var.container_registry_id != null ? 1 : 0

  scope                = var.container_registry_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.this.principal_id
}

# Grant Key Vault access
resource "azurerm_role_assignment" "keyvault_secrets_user" {
  count = var.key_vault_id != null ? 1 : 0

  scope                = var.key_vault_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.this.principal_id
}

# Wait for RBAC propagation
resource "time_sleep" "wait_for_rbac" {
  depends_on = [
    azurerm_role_assignment.acr_pull,
    azurerm_role_assignment.keyvault_secrets_user
  ]

  create_duration = "120s"
}

output "id" {
  value = azurerm_user_assigned_identity.this.id
}

output "principal_id" {
  value = azurerm_user_assigned_identity.this.principal_id
}

output "client_id" {
  value = azurerm_user_assigned_identity.this.client_id
}

output "ready" {
  value      = time_sleep.wait_for_rbac.id
  depends_on = [time_sleep.wait_for_rbac]
}
```

**Update: `terraform/environments/dev/main.tf`**

```hcl
# Create managed identity FIRST
module "managed_identity" {
  source = "../../modules/managed-identity"

  name                  = "id-${local.naming_prefix}"
  resource_group_name   = module.resource_group.name
  location              = module.resource_group.location
  container_registry_id = module.container_registry.id
  key_vault_id          = module.key_vault.id
  tags                  = local.common_tags
}

# Then create Container App with user-assigned identity
module "container_app" {
  source = "../../modules/container-app"

  # ... existing config ...

  # Use user-assigned identity instead of system-assigned
  identity_type = "UserAssigned"
  identity_ids  = [module.managed_identity.id]

  # Now we can safely reference ACR
  container_image = "${module.container_registry.login_server}/applicant-validator:latest"
  registry_server = module.container_registry.login_server

  # Wait for identity RBAC to propagate
  depends_on = [
    module.managed_identity.ready  # This ensures RBAC is ready
  ]
}
```

**Update: `terraform/modules/container-app/main.tf`**

```hcl
resource "azurerm_container_app" "this" {
  # ... existing config ...

  # Support both system-assigned and user-assigned identities
  identity {
    type         = var.identity_type
    identity_ids = var.identity_type == "UserAssigned" ? var.identity_ids : null
  }

  # Registry configuration with proper identity reference
  dynamic "registry" {
    for_each = var.registry_server != null ? [1] : []
    content {
      server = var.registry_server
      # For user-assigned identity, reference the identity
      identity = var.identity_type == "UserAssigned" ? var.identity_ids[0] : null
    }
  }
}

# Remove the ACR role assignment from this module
# It's now handled by the managed-identity module
```

### Solution 2: Two-Stage Deployment with Placeholder Image

**Create: `terraform/scripts/push-placeholder-image.sh`**

```bash
#!/bin/bash
set -e

REGISTRY_NAME=$1
IMAGE_NAME=${2:-applicant-validator}

if [ -z "$REGISTRY_NAME" ]; then
  echo "Usage: $0 <registry-name> [image-name]"
  exit 1
fi

echo "Creating placeholder image for $REGISTRY_NAME/$IMAGE_NAME..."

# Create minimal Dockerfile
cat > /tmp/Dockerfile.placeholder <<'EOF'
FROM nginx:alpine
RUN echo '{"status": "placeholder"}' > /usr/share/nginx/html/health.json
EXPOSE 8080
CMD ["nginx", "-g", "daemon off;"]
EOF

# Build and push
az acr login --name "$REGISTRY_NAME"

docker build -t "$REGISTRY_NAME.azurecr.io/$IMAGE_NAME:placeholder" \
  -f /tmp/Dockerfile.placeholder \
  /tmp

docker push "$REGISTRY_NAME.azurecr.io/$IMAGE_NAME:placeholder"

echo "✅ Placeholder image pushed to $REGISTRY_NAME.azurecr.io/$IMAGE_NAME:placeholder"
```

**Update deployment flow:**

```hcl
# terraform/environments/dev/main.tf

locals {
  # Use placeholder tag initially, then switch to latest
  container_image_tag = var.use_placeholder_image ? "placeholder" : "latest"
  container_image     = "${module.container_registry.login_server}/applicant-validator:${local.container_image_tag}"
}

module "container_app" {
  # ... config ...

  container_image = local.container_image
  registry_server = module.container_registry.login_server

  # First deployment must use placeholder
  lifecycle {
    precondition {
      condition     = var.use_placeholder_image == true || var.deployment_phase != "initial"
      error_message = "First deployment must use placeholder image. Set use_placeholder_image = true"
    }
  }
}
```

**Create: `terraform/environments/dev/terraform.tfvars`**

```hcl
# ... existing vars ...

# Set to true for initial deployment, false after
use_placeholder_image = false
deployment_phase      = "production"  # "initial" or "production"
```

### Solution 3: Conditional Registry Configuration

**Smart registry configuration that adapts:**

```hcl
# terraform/modules/container-app/main.tf

locals {
  # Detect if image is from public registry
  is_public_image = can(regex("^(mcr\\.microsoft\\.com|docker\\.io|ghcr\\.io)", var.container_image))

  # Only configure registry for private images
  use_registry_auth = !local.is_public_image && var.registry_server != null
}

resource "azurerm_container_app" "this" {
  # ... config ...

  # Only add registry block for private registries
  dynamic "registry" {
    for_each = local.use_registry_auth ? [1] : []
    content {
      server   = var.registry_server
      identity = var.identity_type == "UserAssigned" ? var.identity_ids[0] : null
    }
  }
}
```

---

## Complete Improved Deployment Flow

### Recommended Architecture

```
1. Provider Registration (auto)
   ↓
2. Resource Group
   ↓
3. Container Registry
   ↓
4. User-Assigned Managed Identity
   ↓
5. RBAC Assignments (ACR + Key Vault)
   ↓
6. Wait for RBAC Propagation (120s)
   ↓
7. Container App (with identity)
   ↓
8. Success!
```

### Updated File Structure

```
terraform/
├── modules/
│   ├── managed-identity/       # NEW: Separate identity module
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── container-app/
│   └── ...
├── environments/
│   └── dev/
│       ├── main.tf             # Updated with proper dependencies
│       ├── providers-setup.tf  # NEW: Provider registration
│       ├── Makefile           # NEW: Automated workflow
│       └── ...
└── scripts/
    ├── preflight-check.sh     # NEW: Pre-deployment checks
    └── push-placeholder-image.sh  # NEW: Placeholder image
```

---

## Implementation Priority

### Phase 1: Quick Wins (Do Now)
1. ✅ Add `time_sleep` resources for RBAC propagation
2. ✅ Add provider registration to Terraform
3. ✅ Create preflight check script

### Phase 2: Best Practices (Do Next)
4. ✅ Implement user-assigned managed identity
5. ✅ Add Makefile for standardized deployment
6. ✅ Update documentation with new flow

### Phase 3: Advanced (Future)
7. ⬜ Implement placeholder image automation
8. ⬜ Add retry logic for transient failures
9. ⬜ Create reusable Terraform module library

---

## Testing the Improvements

### Test Plan

```bash
# 1. Clean slate
terraform destroy -auto-approve

# 2. Run preflight checks
./terraform/scripts/preflight-check.sh

# 3. Deploy with improvements
make deploy

# 4. Verify no manual intervention needed
# Should complete without any 403 errors or missing providers
```

### Success Criteria
- ✅ Zero manual intervention required
- ✅ No RBAC 403 errors
- ✅ No provider registration errors
- ✅ Container App deploys with ACR image on first try
- ✅ Deployment time < 10 minutes

---

## Cost Impact

These improvements add:
- **$0/month** - Time resources are free
- **~60-180 seconds** to deployment time (RBAC wait periods)
- **Better reliability** - Worth the wait time

---

## References

- [Azure RBAC Propagation](https://learn.microsoft.com/en-us/azure/role-based-access-control/troubleshooting#symptom---role-assignment-changes-are-not-being-detected)
- [Terraform Time Provider](https://registry.terraform.io/providers/hashicorp/time/latest/docs)
- [Azure Container Apps Managed Identity](https://learn.microsoft.com/en-us/azure/container-apps/managed-identity)
- [User-Assigned Identity Best Practices](https://learn.microsoft.com/en-us/azure/active-directory/managed-identities-azure-resources/how-manage-user-assigned-managed-identities)
