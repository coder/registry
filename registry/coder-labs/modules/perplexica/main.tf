terraform {
  required_version = ">= 1.0"

  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.5"
    }
  }
}

variable "agent_id" {
  type        = string
  description = "The ID of a Coder agent."
}

variable "docker_socket" {
  type        = string
  description = "(Optional) Docker socket URI"
  default     = ""
}

variable "port" {
  type        = number
  description = "The port to run Perplexica on."
  default     = 3000
}

variable "data_path" {
  type        = string
  description = "Host path to mount for Perplexica data persistence."
  default     = "./perplexica-data"
}

variable "uploads_path" {
  type        = string
  description = "Host path to mount for Perplexica file uploads."
  default     = "./perplexica-uploads"
}

variable "openai_api_key" {
  type        = string
  description = "OpenAI API key."
  default     = ""
  sensitive   = true
}

variable "anthropic_api_key" {
  type        = string
  description = "Anthropic API key for Claude models."
  default     = ""
  sensitive   = true
}

variable "ollama_api_url" {
  type        = string
  description = "Ollama API URL for local LLM support."
  default     = ""
}

variable "share" {
  type    = string
  default = "owner"
  validation {
    condition     = var.share == "owner" || var.share == "authenticated" || var.share == "public"
    error_message = "Incorrect value. Please set either 'owner', 'authenticated', or 'public'."
  }
}

variable "order" {
  type        = number
  description = "The order determines the position of app in the UI presentation. The lowest order is shown first and apps with equal order are sorted by name (ascending order)."
  default     = null
}

variable "group" {
  type        = string
  description = "The name of a group that this app belongs to."
  default     = null
}

resource "coder_script" "perplexica" {
  agent_id     = var.agent_id
  display_name = "Perplexica"
  icon         = "/icon/perplexica.svg"
  script = templatefile("${path.module}/run.sh", {
    DOCKER_HOST : var.docker_socket,
    PORT : var.port,
    DATA_PATH : var.data_path,
    UPLOADS_PATH : var.uploads_path,
    OPENAI_API_KEY : var.openai_api_key,
    ANTHROPIC_API_KEY : var.anthropic_api_key,
    OLLAMA_API_URL : var.ollama_api_url,
  })
  run_on_start = true
}

resource "coder_app" "perplexica" {
  agent_id     = var.agent_id
  slug         = "perplexica"
  display_name = "Perplexica"
  url          = "http://localhost:${var.port}"
  icon         = "/icon/perplexica.svg"
  subdomain    = true
  share        = var.share
  order        = var.order
  group        = var.group
}
