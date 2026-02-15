#------------------------------------------------------------------------------
# Terraform Makefile - Development Environment
#------------------------------------------------------------------------------
# Standardized workflow for Terraform operations with built-in safety checks
#
# Usage:
#   make preflight    - Run pre-deployment checks
#   make init         - Initialize Terraform (with backend)
#   make plan         - Plan infrastructure changes
#   make apply        - Apply infrastructure changes
#   make deploy       - Full deployment (preflight + init + plan + apply)
#   make destroy      - Destroy all infrastructure
#   make output       - Show Terraform outputs
#   make fmt          - Format Terraform files
#   make validate     - Validate Terraform configuration
#   make clean        - Clean Terraform cache
#------------------------------------------------------------------------------

.PHONY: help preflight init plan apply deploy destroy output fmt validate clean test

# Default target - show help
help:
	@echo ""
	@echo "FinRisk Platform - Terraform Makefile"
	@echo "======================================"
	@echo ""
	@echo "Available targets:"
	@echo "  make preflight   - Run pre-deployment checks"
	@echo "  make init        - Initialize Terraform with backend"
	@echo "  make plan        - Plan infrastructure changes"
	@echo "  make apply       - Apply infrastructure changes"
	@echo "  make deploy      - Full deployment (recommended)"
	@echo "  make destroy     - Destroy all infrastructure"
	@echo "  make output      - Show Terraform outputs"
	@echo "  make fmt         - Format Terraform files"
	@echo "  make validate    - Validate configuration"
	@echo "  make clean       - Clean Terraform cache"
	@echo ""

# Pre-flight checks before any Terraform operation
preflight:
	@echo "Running pre-flight checks..."
	@../../scripts/preflight-check.sh

# Initialize Terraform (with preflight)
init: preflight
	@echo "Initializing Terraform..."
	@if [ ! -f backend.hcl ]; then \
		echo "❌ Error: backend.hcl not found"; \
		echo "   Copy backend.hcl.example to backend.hcl and configure"; \
		exit 1; \
	fi
	@if [ ! -f terraform.tfvars ]; then \
		echo "❌ Error: terraform.tfvars not found"; \
		echo "   Copy terraform.tfvars.example to terraform.tfvars and configure"; \
		exit 1; \
	fi
	terraform init -backend-config=backend.hcl

# Format Terraform code
fmt:
	@echo "Formatting Terraform files..."
	terraform fmt -recursive ../../..

# Validate Terraform configuration
validate: init
	@echo "Validating Terraform configuration..."
	terraform validate

# Plan infrastructure changes
plan: init validate
	@echo "Planning infrastructure changes..."
	terraform plan -out=tfplan

# Apply infrastructure changes
apply: plan
	@echo ""
	@echo "⚠️  Warning: This will modify Azure infrastructure"
	@echo ""
	@read -p "Continue? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		echo "Applying infrastructure changes..."; \
		terraform apply tfplan; \
	else \
		echo "Apply cancelled."; \
		exit 1; \
	fi

# Full deployment (one command)
deploy: preflight init validate plan
	@echo ""
	@echo "╔══════════════════════════════════════════════════════════════════════════════╗"
	@echo "║                                                                              ║"
	@echo "║                    Ready to Deploy Infrastructure                            ║"
	@echo "║                                                                              ║"
	@echo "╚══════════════════════════════════════════════════════════════════════════════╝"
	@echo ""
	@echo "✅ Pre-flight checks passed"
	@echo "✅ Terraform initialized"
	@echo "✅ Configuration validated"
	@echo "✅ Plan generated"
	@echo ""
	@read -p "Deploy infrastructure? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		echo "Deploying infrastructure..."; \
		terraform apply tfplan; \
		echo ""; \
		echo "✅ Deployment complete!"; \
		echo ""; \
		terraform output; \
	else \
		echo "Deployment cancelled."; \
		exit 1; \
	fi

# Destroy infrastructure (with confirmation)
destroy: init
	@echo ""
	@echo "⚠️  WARNING: This will DESTROY all infrastructure!"
	@echo ""
	@echo "Resources to be destroyed:"
	@terraform state list
	@echo ""
	@read -p "Type 'destroy' to confirm: " -r; \
	echo; \
	if [ "$$REPLY" = "destroy" ]; then \
		echo "Destroying infrastructure..."; \
		terraform destroy; \
	else \
		echo "Destroy cancelled."; \
		exit 1; \
	fi

# Show Terraform outputs
output: init
	@terraform output

# Show outputs in JSON format
output-json: init
	@terraform output -json

# Clean Terraform cache
clean:
	@echo "Cleaning Terraform cache..."
	rm -rf .terraform
	rm -f .terraform.lock.hcl
	rm -f tfplan
	rm -f terraform.tfstate.backup
	@echo "✅ Clean complete"

# Refresh Terraform state
refresh: init
	@echo "Refreshing Terraform state..."
	terraform refresh

# Show current Terraform state
show: init
	@terraform show

# List resources in state
list: init
	@terraform state list

# Run all tests (validation + plan)
test: init validate
	@echo "Running Terraform tests..."
	terraform plan -detailed-exitcode || exit 0
	@echo "✅ All tests passed"

# Quick status check
status:
	@echo ""
	@echo "FinRisk Platform - Infrastructure Status"
	@echo "========================================"
	@echo ""
	@if [ -d .terraform ]; then \
		echo "✅ Terraform initialized"; \
	else \
		echo "❌ Terraform not initialized (run: make init)"; \
	fi
	@if [ -f backend.hcl ]; then \
		echo "✅ Backend configured"; \
	else \
		echo "❌ Backend not configured (copy backend.hcl.example)"; \
	fi
	@if [ -f terraform.tfvars ]; then \
		echo "✅ Variables configured"; \
	else \
		echo "❌ Variables not configured (copy terraform.tfvars.example)"; \
	fi
	@if az account show &>/dev/null; then \
		ACCOUNT=$$(az account show --query name -o tsv); \
		echo "✅ Azure authenticated ($$ACCOUNT)"; \
	else \
		echo "❌ Not authenticated to Azure (run: az login)"; \
	fi
	@echo ""
