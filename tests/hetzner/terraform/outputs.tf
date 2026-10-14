output "vms" {
  description = "All VMs with their IDs and addresses"
  value = {
    for name, s in hcloud_server.vm : name => {
      id          = s.id
      image       = local.vms[name].image
      server_type = s.server_type
      public_ipv4 = s.ipv4_address
      public_ipv6 = s.ipv6_address
      private_ip  = local.vms[name].private_ip
      fqdn        = local.vms[name].fqdn
    }
  }
}

output "private_network_id" {
  description = "ID of the private Hetzner Cloud network the VMs are attached to"
  value       = hcloud_network.internal_network.id
}

output "ssh_commands" {
  description = "Ready-to-paste SSH command per VM"
  value = {
    for name, s in hcloud_server.vm : name => "ssh -i ${local.provisioning_private_key_path} ${var.ssh_user}@${s.ipv4_address}"
  }
}

output "inventory_path" {
  description = "Generated Ansible inventory"
  value       = abspath(local_file.inventory.filename)
}
