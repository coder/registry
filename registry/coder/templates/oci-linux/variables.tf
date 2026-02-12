variable "tenancy_ocid" {
  description = "The OCID of your tenancy."
  type        = string
  sensitive   = true
}

variable "user_ocid" {
  description = "The OCID of the user calling the API."
  type        = string
  sensitive   = true
}

variable "fingerprint" {
  description = "The fingerprint for the API key."
  type        = string
  sensitive   = true
}

variable "private_key_path" {
  description = "The path to the private key used for authentication."
  type        = string
  sensitive   = true
}

variable "region" {
  description = "The OCI region (e.g. us-ashburn-1)."
  type        = string
}

variable "compartment_ocid" {
  description = "The OCID of the compartment to contain the resources."
  type        = string
  sensitive   = true
}

variable "instance_shape" {
  description = "The shape of the instance."
  default     = "VM.Standard.A1.Flex"
}

variable "image_id" {
  description = "The OCID of an Ubuntu image (or other Linux) in your region."
  type        = string
}
