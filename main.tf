provider "azurerm" {
  version = "=2.10.0"
  features {}
}

resource "random_string" "unique" {
  length  = 6
  special = false
  upper   = false
}

resource "azurerm_resource_group" "rg" {
  name     = "rg-${random_string.unique.result}"
  location = var.rg_location
}

resource "azurerm_kubernetes_cluster" "aks" {
  name                = "aks-${random_string.unique.result}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  kubernetes_version  = var.aks_version
  dns_prefix          = "aks"

  default_node_pool {
    name       = "default"
    node_count = var.aks_node_count
    vm_size    = var.aks_vm_size
  }

  identity {
    type = "SystemAssigned"
  }

  role_based_access_control {
    enabled = true
  }
}

provider "helm" {
  kubernetes {
    load_config_file       = false
    host                   = azurerm_kubernetes_cluster.aks.kube_config.0.host
    username               = azurerm_kubernetes_cluster.aks.kube_config.0.username
    password               = azurerm_kubernetes_cluster.aks.kube_config.0.password
    client_certificate     = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.client_certificate)
    client_key             = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.client_key)
    cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.cluster_ca_certificate)
  }
}

resource "azurerm_public_ip" "ingress" {
  name                = "pip-${random_string.unique.result}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_kubernetes_cluster.aks.node_resource_group
  domain_name_label   = random_string.unique.result
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  namespace        = var.cert_manager_ns
  create_namespace = true
  version          = "v0.15.0"

  set {
    name  = "installCRDs"
    value = true
  }
}

resource "helm_release" "ingress" {
  name             = "nginx-ingress"
  repository       = "https://kubernetes-charts.storage.googleapis.com"
  chart            = "nginx-ingress"
  namespace        = var.ingress_ns
  create_namespace = true

  # Until Helm really fixes this issue (and not just mark it as closed), keep this flag false
  # https://github.com/helm/charts/issues/11904
  wait = false

  set {
    name  = "controller.replicaCount"
    value = var.ingress_replica_count
  }

  set {
    name  = "controller.service.loadBalancerIP"
    value = azurerm_public_ip.ingress.ip_address
  }

  set {
    name  = "controller.nodeSelector.beta\\.kubernetes\\.io/os"
    value = "linux"
    type  = "string"
  }

  set {
    name  = "defaultBackend.nodeSelector.beta\\.kubernetes\\.io/os"
    value = "linux"
    type  = "string"
  }

  set {
    name  = "controller.extraArgs.default-ssl-certificate"
    value = "${helm_release.cert_manager.namespace}/${var.default_cert_secret_name}"
  }
}

resource "local_file" "kube_config" {
  filename          = "${path.module}/kubeconfig"
  sensitive_content = azurerm_kubernetes_cluster.aks.kube_config_raw
}

locals {
  cert_manager_yaml = "${path.module}/cert-manager.yaml"
}

resource "null_resource" "cert_manager" {
  triggers = {
    kube_config              = sha1(azurerm_kubernetes_cluster.aks.kube_config_raw)
    cert_manager_ns          = helm_release.cert_manager.namespace
    default_cert_secret_name = var.default_cert_secret_name
    fqdn                     = azurerm_public_ip.ingress.fqdn
    cert_manager_sha1        = filesha1(local.cert_manager_yaml)
  }

  provisioner "local-exec" {
    environment = {
      KUBECONFIG               = local_file.kube_config.filename
      DEFAULT_CERT_SECRET_NAME = var.default_cert_secret_name
      FQDN                     = azurerm_public_ip.ingress.fqdn
    }
    command = <<EOF
      envsubst < ${local.cert_manager_yaml} | kubectl apply -n ${helm_release.cert_manager.namespace} -f -
EOF
  }

  depends_on = [
    helm_release.ingress,
    helm_release.cert_manager
  ]
}
