# Optional raw disk per VM, deliberately left unformatted and unmounted.
resource "hcloud_volume" "data" {
  for_each = { for name, vm in local.vms : name => vm if vm.volume_size > 0 }
  name     = "${each.key}-data"
  size     = each.value.volume_size
  location = var.location
}

resource "hcloud_volume_attachment" "data" {
  for_each  = hcloud_volume.data
  volume_id = each.value.id
  server_id = hcloud_server.vm[each.key].id
  automount = false
}
