job "shortcircuit-masque" {
  datacenters = ["dc1"]
  type        = "system"

  group "transport" {
    task "masque-bridge" {
      driver = "raw_exec"

      config {
        command = "/usr/local/bin/masque-client"
        args    = [
          "-listen", "127.0.0.1:4243",
          "-upstream", "YOUR_LIGHTHOUSE_IP:443",
          "-cert", "/etc/nebula/ca.crt"
        ]
      }

      resources {
        cpu    = 100
        memory = 64
      }
    }
  }
}
