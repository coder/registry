terraform {
  required_version = ">= 1.0"
  
  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 0.21.0"
    }
  }
}

