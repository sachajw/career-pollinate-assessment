variable "name" {
  description = "Name of the resource group"
  type        = string

  validation {
    condition     = can(regex("^rg-", var.name))
    error_message = "Resource group name must start with 'rg-'"
  }
}

variable "location" {
  description = "Azure region for the resource group"
  type        = string

  validation {
    condition     = contains(["eastus2", "westus2", "centralus"], var.location)
    error_message = "Location must be one of: eastus2, westus2, centralus"
  }
}

variable "tags" {
  description = "Tags to apply to the resource group"
  type        = map(string)
  default     = {}
}
