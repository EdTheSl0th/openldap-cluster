resource "hcloud_network" "internal_network" {
  name     = "${var.env_name}-net"
  ip_range = "10.0.0.0/16"
}

resource "hcloud_network_subnet" "server-subnet" {
  network_id   = hcloud_network.internal_network.id
  type         = "server"
  network_zone = "eu-central"
  ip_range     = "10.0.1.0/24"
}
