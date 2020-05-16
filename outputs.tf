output rg_name {
  value = azurerm_resource_group.rg.name
}

output aks_cluster_name {
  value = azurerm_kubernetes_cluster.aks.name
}

output ingress_fqdn {
  value = azurerm_public_ip.ingress_controller.fqdn
}
