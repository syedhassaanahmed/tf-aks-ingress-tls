variable rg_location {
  default = "westeurope"
}

variable aks_version {
  default = "1.16.7"
}

variable aks_node_count {
  default = 1
}

variable aks_vm_size {
  default = "Standard_D2_v2"
}

variable cert_manager_ns {
  default = "cert-manager"
}

variable default_cert_secret_name {
  default = "tls-secret"
}

variable ingress_namespace {
  default = "ingress"
}

variable ingress_replica_count {
  default = 3
}
