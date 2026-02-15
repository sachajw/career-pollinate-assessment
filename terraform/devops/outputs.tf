#------------------------------------------------------------------------------
# Azure DevOps Environment Outputs
#------------------------------------------------------------------------------

output "pipeline_url" {
  description = "URL to the CI/CD pipeline"
  value       = module.azure_devops.build_definition_url
}

output "github_connection_id" {
  description = "GitHub service connection ID"
  value       = module.azure_devops.github_service_connection_id
}

output "azure_connection_id" {
  description = "Azure service connection ID"
  value       = module.azure_devops.azurerm_service_connection_id
}

output "instructions" {
  description = "Next steps after apply"
  value = <<-EOT

    ✅ Azure DevOps is now connected to GitHub!

    Next steps:
    1. Go to ${module.azure_devops.build_definition_url}
    2. Click "Run pipeline" to trigger first deployment
    3. Monitor the build in Azure DevOps

    Your pipeline will:
    - Build the Docker image
    - Push to ACR (acrfinriskdev.azurecr.io)
    - Deploy to Container Apps (ca-finrisk-dev)
    - Run health checks

  EOT
}
