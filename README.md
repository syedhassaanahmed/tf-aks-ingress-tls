# tf-aks-ingress-tls
![Terraform](https://github.com/syedhassaanahmed/tf-aks-ingress-tls/workflows/Terraform/badge.svg)

This Terraform template is loosely based on [this document](https://docs.microsoft.com/en-us/azure/aks/ingress-static-ip). It provisions an AKS Cluster with [NGINX Ingress Controller](https://kubernetes.github.io/ingress-nginx/) and issues LetsEncrypt TLS certificate using [cert-manager](https://cert-manager.io/docs/).

## Requirements
- [Terraform](https://www.terraform.io/downloads.html)
- [kubectl](https://docs.microsoft.com/en-us/cli/azure/aks?view=azure-cli-latest#az-aks-install-cli)
- [gettext](https://www.gnu.org/software/gettext/)

## Caveats
- In order to avoid [LetsEncrypt rate limits](https://letsencrypt.org/docs/rate-limits/), we use the [Staging](https://letsencrypt.org/docs/staging-environment/) endpoint in default certificate. If you'd like to switch to the prod endpoint, change the [issuerRef.name](https://github.com/syedhassaanahmed/tf-aks-ingress-tls/blob/a37efb42b91ac38538f72b1add947fb8ae140359/cert-manager.yaml#L40) to `letsencrypt-prod`.
- If you've deployed AKS in your own VNET, the NSG must allow inbound traffic on port 80 in order for `cert-manager` to successfully perform the [HTTP-01 challenge](https://letsencrypt.org/docs/challenge-types/#http-01-challenge). IP whitelisting is unfortunately not possible because [LetsEncrypt doesn't publish them](https://letsencrypt.org/docs/faq/#what-ip-addresses-does-let-s-encrypt-use-to-validate-my-web-server).
```terraform
resource "azurerm_network_security_rule" "aks_inbound" {
  name                        = "aks-inbound"
  resource_group_name         = azurerm_resource_group.rg.name
  network_security_group_name = azurerm_network_security_group.nsg.name
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_ranges     = ["80", "443"]
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  access                      = "Allow"
  priority                    = 1001
  direction                   = "Inbound"
}
```

## Smoke Test
Once `terraform apply` has successfully completed, fill the following variable from the Terraform output;
```sh
export ingress_fqdn="xxxxxx.westeurope.cloudapp.azure.com"
```
Then;
```
./smoke_test.sh
```
The smoke test will create a test deployment, service and ingress in the newly provisioned AKS cluster.
