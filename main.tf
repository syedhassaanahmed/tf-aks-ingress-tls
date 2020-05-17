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

provider "kubernetes" {
  load_config_file       = false
  host                   = azurerm_kubernetes_cluster.aks.kube_config.0.host
  username               = azurerm_kubernetes_cluster.aks.kube_config.0.username
  password               = azurerm_kubernetes_cluster.aks.kube_config.0.password
  client_certificate     = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.client_certificate)
  client_key             = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.client_key)
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.cluster_ca_certificate)
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

resource "kubernetes_namespace" "ingress" {
  metadata {
    labels = {
      name = var.ingress_ns
    }
    name = var.ingress_ns
  }
}

resource "kubernetes_namespace" "cert_manager" {
  metadata {
    labels = {
      name = var.cert_manager_ns
    }
    name = var.cert_manager_ns
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

resource "helm_release" "ingress" {
  name       = "nginx-ingress"
  repository = "https://kubernetes-charts.storage.googleapis.com"
  chart      = "nginx-ingress"
  namespace  = kubernetes_namespace.ingress.metadata.0.name

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
    name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/azure-dns-label-name"
    value = azurerm_public_ip.ingress.domain_name_label
    type  = "string"
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
    value = "${kubernetes_namespace.cert_manager.metadata.0.name}/${var.default_cert_secret_name}"
  }
}

resource "helm_release" "cert_manager" {
  name       = "cert-manager"
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  namespace  = kubernetes_namespace.cert_manager.metadata.0.name
  version    = "v0.15.0"

  set {
    name  = "installCRDs"
    value = true
  }
}

locals {
  kube_config_path  = "${path.module}/.kube"
  cert_manager_yaml = "${path.module}/cert-manager.yaml"
}

resource "null_resource" "kube_config" {
  triggers = {
    always = timestamp()
  }

  provisioner "local-exec" {
    environment = {
      KUBE_CONFIG_RAW = azurerm_kubernetes_cluster.aks.kube_config_raw
    }
    command = <<EOF
      echo "$KUBE_CONFIG_RAW" > ${local.kube_config_path}
EOF
  }
}

resource "null_resource" "cert_manager" {
  triggers = {
    kube_config              = azurerm_kubernetes_cluster.aks.kube_config_raw
    cert_manager_ns          = kubernetes_namespace.cert_manager.metadata.0.name
    default_cert_secret_name = var.default_cert_secret_name
    fqdn                     = azurerm_public_ip.ingress.fqdn
    cert_manager_sha1        = filesha1(local.cert_manager_yaml)
  }

  provisioner "local-exec" {
    environment = {
      KUBECONFIG               = local.kube_config_path
      DEFAULT_CERT_SECRET_NAME = var.default_cert_secret_name
      FQDN                     = azurerm_public_ip.ingress.fqdn
    }
    command = <<EOF
      envsubst < ${local.cert_manager_yaml} | kubectl apply -n ${kubernetes_namespace.cert_manager.metadata.0.name} -f -
EOF
  }

  depends_on = [
    helm_release.ingress,
    helm_release.cert_manager,
    null_resource.kube_config
  ]
}
