#------------------------------------------------------------------------------
# Azure Resource Group Module - variables.tf
#------------------------------------------------------------------------------
# Input variable definitions for the resource group module.
# All variables include descriptions, types, and validation where appropriate.
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Required Variables
#------------------------------------------------------------------------------

# name - The name of the resource group
# Must start with 'rg-' prefix to follow naming convention
# Example: rg-riskscoring-dev, rg-myapp-prod
variable "name" {
  description = "Name of the resource group (must follow naming convention: rg-{project}-{env})"
  type        = string

  # Validation: Ensure name starts with 'rg-' prefix
  validation {
    condition     = can(regex("^rg-", var.name))
    error_message = "Resource group name must start with 'rg-' (e.g., rg-myapp-dev)"
  }
}

# location - The Azure region for the resource group
# Restricted to approved regions for cost and compliance reasons
variable "location" {
  description = "Azure region for the resource group"
  type        = string

  # Validation: Restrict to approved Azure regions
  # Add more regions here as needed for your organization
  validation {
    condition     = contains(["eastus", "eastus2", "westus2", "centralus"], var.location)
    error_message = "Location must be one of the approved regions: eastus, eastus2, westus2, centralus"
  }
}

#------------------------------------------------------------------------------
# Optional Variables
#------------------------------------------------------------------------------

# tags - Key-value pairs for resource organization
# Common tags: Environment, Project, ManagedBy, CostCenter, Owner, Compliance
variable "tags" {
  description = "Tags to apply to the resource group for organization and cost management"
  type        = map(string)
  default     = {}
}
