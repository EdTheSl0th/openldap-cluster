variable "hcloud_token" {
  description = "Token for your Hetzner-Cloud-Account (or set TF_VAR_hcloud_token)"
  type        = string
  sensitive   = true
}

variable "admin_ips" {
  description = "Which IPs (CIDR) may access the VMs"
  type        = list(string)
}

variable "env_name" {
  description = "Prefix for project-wide Hetzner resources (network, firewall, SSH key)"
  type        = string
  default     = "ansible-test"
}

variable "location" {
  description = "Location of the servers"
  type        = string
  default     = "nbg1"
}

variable "domain" {
  description = "Domain used for the FQDN of the VMs"
  type        = string
  default     = "test.internal"
}

variable "ssh_user" {
  description = "Sudo user Ansible connects as"
  type        = string
  default     = "ansible"
}

variable "default_image" {
  description = "Image for VMs that don't set one (see `hcloud image list`)"
  type        = string
  default     = "debian-13"
}

variable "default_server_type" {
  description = "Server type for VMs that don't set one"
  type        = string
  default     = "cpx22"
}

variable "vms" {
  description = "Test VMs by hostname. Every attribute is optional."
  type = map(object({
    image       = optional(string)
    server_type = optional(string)
    groups      = optional(list(string), [])
    private_ip  = optional(string)
    volume_size = optional(number, 0)
  }))
  default = { "vm-1" = {} }

  validation {
    condition     = alltrue([for name in keys(var.vms) : can(regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$", name))])
    error_message = "VM names must be valid hostnames (lowercase letters, digits, hyphens)."
  }

  validation {
    condition     = alltrue(flatten([for vm in values(var.vms) : [for g in vm.groups : can(regex("^[A-Za-z_][A-Za-z0-9_]*$", g))]]))
    error_message = "Group names may only contain letters, digits and underscores and must not start with a digit."
  }
}

variable "extra_ports" {
  description = "Additional inbound ports opened for admin_ips, e.g. [{ port = \"443\" }, { port = \"8000-8100\", protocol = \"udp\" }]"
  type = list(object({
    port     = string
    protocol = optional(string, "tcp")
  }))
  default = []
}
