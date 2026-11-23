variable "resource_group_name" {
  description = "Existing resource group that receives the whole foundation"
  type        = string
}

variable "location" {
  description = "Azure region for every resource"
  type        = string
  default     = "eastus"
}

variable "prefix" {
  description = "Short company name used in resource names"
  type        = string
  default     = "contoso"

  validation {
    condition     = can(regex("^[a-z0-9]{2,10}$", var.prefix))
    error_message = "Use 2-10 lowercase letters or digits (it goes into the storage name)."
  }
}

variable "web_allowed_source" {
  description = "CIDR allowed to reach the published web app, e.g. 203.0.113.10/32"
  type        = string

  validation {
    condition     = can(cidrhost(var.web_allowed_source, 0))
    error_message = "Use a CIDR such as 203.0.113.10/32."
  }
}
