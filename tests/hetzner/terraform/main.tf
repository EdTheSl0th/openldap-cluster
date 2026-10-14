locals {
  subnet_cidr     = hcloud_network_subnet.server-subnet.ip_range
  firewall_ids    = [hcloud_firewall.fw.id]
  ssh_public_keys = [hcloud_ssh_key.provisioning_key.id]

  # Automatic private IPs start at .11, assigned in alphabetical order of the
  # VM names. Set private_ip on a VM to pin it.
  vm_names = sort(keys(var.vms))

  vms = {
    for name, vm in var.vms : name => {
      image       = coalesce(vm.image, var.default_image)
      server_type = coalesce(vm.server_type, var.default_server_type)
      groups      = vm.groups
      volume_size = vm.volume_size
      private_ip  = coalesce(vm.private_ip, cidrhost("10.0.1.0/24", index(local.vm_names, name) + 11))
      fqdn        = "${name}.${var.domain}"
      image_group = replace(replace(coalesce(vm.image, var.default_image), "-", "_"), ".", "_")
    }
  }

  # Inventory groups: "test" (all VMs), one per image, plus the custom groups.
  group_names = distinct(concat(
    ["test"],
    [for vm in values(local.vms) : vm.image_group],
    flatten([for vm in values(local.vms) : vm.groups]),
  ))

  groups = {
    for g in local.group_names : g => sort([
      for name, vm in local.vms : name
      if g == "test" || g == vm.image_group || contains(vm.groups, g)
    ])
  }
}
