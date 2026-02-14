# Resource Group Module - Complete Example
# This example demonstrates all configuration options

module "resource_group" {
  source = "../.."

  name     = "rg-example-complete"
  location = "eastus2"

  tags = {
    Environment = "dev"
    Project     = "terraform-modules"
    ManagedBy   = "terraform"
    CostCenter  = "engineering"
    Owner       = "platform-team"
  }
}

# Output the resource group details
output "resource_group_id" {
  description = "The ID of the created resource group"
  value       = module.resource_group.id
}

output "resource_group_name" {
  description = "The name of the created resource group"
  value       = module.resource_group.name
}

output "resource_group_location" {
  description = "The location of the created resource group"
  value       = module.resource_group.location
}
