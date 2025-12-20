# Networking within the Azure Landing Zone

Last updated: **{{ git_revision_date_localized }}**

The following sections describe the networking components within the Azure Landing Zone, including the Virtual Network (VNet), spoke-to-spoke connectivity, and internet connectivity.

!!! warning "Subnet planning"
    It is **crucial** that you plan out your subnetting strategy **before** deploying resources in the Azure Landing Zone. This will help prevent any potential issues that would require re-architecting your network later on.

!!! warning "Subnet delegation"
    Depending on your solution architecture and which Azure services you are using, you may need to use [subnet delegation](https://learn.microsoft.com/en-us/azure/virtual-network/manage-subnet-delegation?tabs=manage-subnet-delegation-portal) to allow certain Azure services to create resources in your subnets.

Understand the impact, especially in Production environments. **Plan your subnet sizes carefully**.
Once you deploy resources in a subnet, you cannot change its delegation unless you remove all resources. You also cannot resize the subnet until you remove the delegation.

## Virtual network (VNet)

Each Project Set in the Azure Landing Zone includes a [Virtual Network (VNet)](https://learn.microsoft.com/en-us/azure/virtual-network/virtual-networks-overview) which isolates and secures deployed resources. This VNet forms the foundation of network connectivity in the Azure Landing Zone.

!!! danger "Allocated IP addresses"
    Each Project Set is provided with approximately **251 IP addresses** (ie. `/24`) by default. If your application requires more IP addresses than the `/24` provides, contact the Public cloud team by submitting a [Service Request](https://citz-do.atlassian.net/servicedesk/customer/portal/3).

    !!! note "Microsoft IP reservations"
        Microsoft **reserves 5 IP addresses** from **each subnet** within a Virtual Network. Therefore a `/24` subnet would not have 256 IP addresses available for use, but rather 251 IP addresses.

This VNet is connected with the central hub (vWAN), and receives default routes to direct all traffic (ie. Internet and private) through the firewall located in the central hub.

There are no subnets that are pre-created within the VNet. Each team is responsible for creating their own subnets based on their requirements. Subnets should be created within the VNet to segment resources based on their function or security requirements.

!!! danger "Security controls for subnets"
    There are some security controls in place, that require every subnet to have an associated [Network Security Group (NSG)](https://learn.microsoft.com/en-us/azure/virtual-network/network-security-groups-overview). This may cause some challenges when creating subnets. The simplest approach is to create a NSG first, and then create the subnet (with the NSG associated with it).

    For further guidance on creating subnets with associated NSGs (specifically using Terraform), refer to the [IaC and CI/CD](../best-practices/iac-and-ci-cd.md#using-terraform-to-create-subnets) documentation.

    Additionally, as part of implementing a **Zero Trust** security model, all subnets need to be created as [Private Subnets](https://learn.microsoft.com/en-us/azure/virtual-network/ip-services/default-outbound-access#utilize-the-private-subnet-parameter-public-preview).

## Spoke-to-Spoke connectivity

If your team has multiple environments (ie. Dev, Test, Prod, Tools) within the same Project Set, you may require connectivity between the different environments. This is known as spoke-to-spoke connectivity.
<!-- TODO: Update to point to the Firewall Request Form once it is released -->
By default, this connectivity is disabled for security reasons. If you require spoke-to-spoke connectivity, you must [submit a request](https://citz-do.atlassian.net/servicedesk/customer/portal/3) to the Public cloud team, who will review the request based on the security requirements, and make any necessary changes in the firewall to allow this type of traffic.

## Internet connectivity

All outbound traffic from the Azure Landing Zone is routed through the central hub and the firewall. This ensures that all traffic is inspected and monitored for security compliance.

Advanced features are implemented and configured including:

- Transport Layer Security (TLS) inspection
  - Protection against malicious traffic that is sent from an internal client hosted in Azure to the Internet
  - Protection against East-West traffic that goes to/from an Azure Virtual Network (VNet), to protect Azure workloads from potential malicious traffic sent from within Azure
- Intrusion Detection and Prevention (IDPS)
  - Signature-based detection (applicable for both application and network-level traffic)
- URL filtering
  - Applied both on HTTP and HTTPS traffic
  - Target URL extraction and validation
- Web categories
  - Allow or deny access to websites based on categories (eg. gambling, social media, etc.)

### Exposing services to the internet

For applications with advanced requirements, an [Azure Application Gateway](https://learn.microsoft.com/en-us/azure/application-gateway/overview) is the recommended way to expose applications to the Internet. It includes an OSI Layer 7 web traffic load balancer to help manage web application traffic.

To adhere to security best practices, the Application Gateway should also be configured with a [Web Application Firewall (WAF)](https://learn.microsoft.com/en-us/azure/application-gateway/features#web-application-firewall) to protect your applications from common exploits and vulnerabilities.

!!! warning "Application Gateway backend health probes"
    Please be aware that the backend health may show a status of **Unknown**. For more information and direction on how to resolve this, see the **Insights on Azure Services** - [Application Gateway](../azure-services/application-gateway.md) documentation.

## VNet integration vs private endpoints

When working with Azure PaaS services, there are multiple ways to [integrate Azure services with virtual networks for network isolation](https://learn.microsoft.com/en-us/azure/virtual-network/vnet-integration-for-azure-services).

While [VNet integration](https://learn.microsoft.com/en-us/azure/virtual-network/virtual-network-for-azure-services), and [Service Endpoints](https://learn.microsoft.com/en-us/azure/virtual-network/virtual-network-service-endpoints-overview) are valid options, the recommended approach is to use [Private Endpoints](https://learn.microsoft.com/en-us/azure/private-link/private-endpoint-overview). This is because there is automation in place that will create the DNS record for the private endpoint in the centralized Private DNS Zone. For more information, please refer to the [Private Endpoints and DNS](../best-practices/be-mindful.md#private-endpoints-and-dns) section on the **Best Practices** page.

## Protected network resources

In order to maintain the security of the Azure Landing Zone, there are certain network resources that are protected and cannot be modified by teams, and other network resources that cannot be created in the Landing Zone. These include:

- Modifying the Virtual Network (VNet) DNS settings
  - This is required so that all traffic is routed through the central firewall, for compliance requirements
- Modifying the Virtual Network (VNet) address space
  - This is required so that overlapping IP address ranges are not created in the Azure Landing Zone
- Creating ExpressRoute circuits, VPN Sites, VPN/NAT/Local Gateways, or Route Tables
  - This is so that traffic is not bypassing the central firewall
- Creating Virtual Networks
  - This is to avoid overlapping IP address ranges that may be in use by other Project Sets
- Creating Virtual Network peering with other VNets
  - This is required to ensure spoke-to-spoke traffic is managed centrally through the firewall
- Deleting the `setbypolicy` Diagnostics Settings
  - You can create your own diagnostics settings for your resources, but you can't delete the default one

# Be mindful

Last updated: **{{ git_revision_date_localized }}**

The following are some things to be aware of when working within the Azure Landing Zone.

## Private Endpoints and DNS

As a security requirement, some Azure PaaS services (ie. Databases, Key Vaults, etc.) have been restricted to private-only connectivity. This means during deployment, you will need to include the creation of a [Private Endpoint](https://learn.microsoft.com/en-us/azure/private-link/private-endpoint-overview) for this service.

As part of creating the Private Endpoint, you will be asked about **Private DNS Integration**. The Azure portal defaults the "**Integrate with private DNS zone**" option to "**Yes**". However, we have the Azure Landing Zones already configured with centralized custom Private DNS Zones, so you should select "**No**" for this option.

![Private Endpoint - Private DNS Integration](../images/private-endpoints-dns.png "Private Endpoint - Private DNS Integration")

Once the Private Endpoint for your resource is deployed, a DNS `A-record` will be automatically created in the custom Private DNS Zone in approximately **10 minutes**, pointing to the private IP address of the resource. This will allow you to access the resource using the custom DNS name within the private network.

However, since the endpoint is private-only, you will not be able to access the resource from outside the VNet. To access and work with these specific resources, you need to use either [Azure Bastion](https://learn.microsoft.com/en-us/azure/bastion/bastion-overview) or an [Azure Virtual Desktop (AVD)](https://learn.microsoft.com/en-us/azure/virtual-desktop/overview) from within the VNet.

In the future, once [ExpressRoute](../design-build-deploy/networking-express-route.md) is available, you will also be able to access these resources from the on-premises network or through a VPN.

## Custom DNS Zones

In some scenarios, you may have a need to create a custom DNS Zone. Generally, this is not recommended, as the Azure Landing Zones are already configured with centralized custom Private DNS Zones for the Azure services. However, when working with third-party services (ie. Confluent Cloud), we might not have a Private DNS Zone for the specific service.

If this is your scenario, please submit a [support request](https://citz-do.atlassian.net/servicedesk/customer/portal/3), so that the Public cloud team can work with you to create and attach the custom DNS Zone to the central Private DNS Resolver.

!!! failure "Private DNS Zone attachment to VNet"
    Attaching your custom Private DNS Zone to your Virtual Network (VNet) will not work, as all DNS queries are routed through the central Private DNS Resolver.
# Infrastructure-as-Code (IaC) and CI/CD

Last updated: **{{ git_revision_date_localized }}**

## Overview

!!! question "Planning to use across subscriptions?"
    If you plan to deploy the [GitHub self-hosted runners](#github-self-hosted-runners-on-azure) or the [Azure DevOps Managed DevOps Pools](#managed-devops-pools-on-azure) into a different Azure subscription than where your resources will be deployed (ie. in your **Tools** subscription), you will need to [submit a firewall request](https://citz-do.atlassian.net/servicedesk/customer/portal/3) to the Public cloud team. This request should state that you need to allow the self-hosted runners/managed devops pool to access resources in another subscription.

!!! note "Terraform and resource tags"
    When using the [Azure Verified Module (AVM) for CICD Agents and Runners](https://github.com/Azure/terraform-azurerm-avm-ptn-cicd-agents-and-runners), the [Azure Verified Module for Managed DevOps Pools](https://github.com/Azure/terraform-azurerm-avm-res-devopsinfrastructure-pool) or any other modules, Terraform may show that it will remove certain tags from resources. This is because the module is not aware of the tags that are set on the resources. If you want to keep the tags, you can add a `lifecycle` block with the [ignore_changes](https://developer.hashicorp.com/terraform/language/meta-arguments/lifecycle#ignore_changes) feature, to the resource in your Terraform code to ignore the tags.

## Terraform

### Using Terraform to create subnets

If you are using Terraform to create your infrastructure, in particular the subnets within your assigned Virtual Network, please be aware of the following challenge.

The Azure Landing Zones have an Azure Policy implemented that requires every subnet to have an associated Network Security Group (NSG) for security controls compliance. The challenge with this is that Terraform doesn't support the creation of subnets with an associated NSG in a _single step_.

Therefore, instead of using the `azurerm_subnet` resource to create subnets, you must use the `azapi_resource` resource from the [AzAPI Terraform Provider](https://registry.terraform.io/providers/Azure/azapi/latest/docs). This resource allows you to create subnets with an associated NSG in a single step.

!!! abstract "AzAPI resource provider"
    You need to use the `azapi_resource` resource, because you are updating an existing Virtual Network (VNet) resource with a new subnet (and associated Network Security Group).

**Example code:**

```terraform
resource "azapi_resource" "subnets" {
  type = "Microsoft.Network/virtualNetworks/subnets@2024-05-01"

  name      = "SubnetName"
  parent_id = data.azurerm_virtual_network.vnet.id
  # Note: Discovered the `locks` attribute for AzAPI from the following GitHub Issue: https://github.com/Azure/terraform-provider-azapi/issues/503
  # A list of ARM resource IDs which are used to avoid create/modify/delete azapi resources at the same time.
  locks = [
    data.azurerm_virtual_network.vnet.id
  ]

  # It's not necessary to use the `jsonencode` function to encode the HCL object to JSON, just use the HCL object directly
  body = {
    properties = {
      networkSecurityGroup = {
        id = azurerm_network_security_group.id
      }
    }
  }

  response_export_values = ["*"]
}
```

For further details about this limitation, please refer to the following GitHub Issue: [Example of using the Subnet Association resources with Azure Policy](https://github.com/hashicorp/terraform-provider-azurerm/issues/9022).

### Using Terraform to create private endpoints

If you are using Terraform to create your infrastructure, in particular Private Endpoints within your assigned Virtual Network, please be aware of the following challenge.

After the Private Endpoint is created, the automation (via Azure Policy) within the Landing Zones will automatically associate the Private Endpoint with the appropriate Private DNS Zone, and create the necessary DNS records (see [Private Endpoints and DNS](./be-mindful.md#private-endpoints-and-dns) for more details).

However, the next time you run `terraform plan` or `terraform apply`, Terraform will detect that this change has occurred outside of your specific Terraform code, and will attempt to **remove** the association between the Private Endpoint and the Private DNS Zone. This will cause issues with resolving your resources via the Private Endpoint.

**Example `terraform plan` output:**

```terraform
  ~ resource "azurerm_private_endpoint" "this" {
        id                            = "/subscriptions/xxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx/resourceGroups/caf-ghr/providers/Microsoft.Network/privateEndpoints/pe-acrghr"
        name                          = "pe-acrghr"

      - private_dns_zone_group {
          - id                   = "/subscriptions/xxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx/resourceGroups/caf-ghr/providers/Microsoft.Network/privateEndpoints/pe-acrghr/privateDnsZoneGroups/deployedByPolicy" -> null
          - name                 = "deployedByPolicy" -> null
          - private_dns_zone_ids = [
              - "/subscriptions/xxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx/resourceGroups/bcgov-managed-lz-forge-dns/providers/Microsoft.Network/privateDnsZones/privatelink.azurecr.io",
            ] -> null
        }
    }
```

While the Azure Policy **_should_** automatically re-associate the Private Endpoint with the Private DNS Zone, it is recommended to add a `lifecycle` block with the [ignore_changes](https://www.terraform.io/docs/language/meta-arguments/lifecycle.html#ignore_changes) feature on the `private_dns_zone_group` resource property in your Terraform code, to ignore the changes that are applied through the Azure Policy.

**Example `terraform lifecycle ignore_changes`:**

```terraform
resource "azurerm_private_endpoint" "example" {
  name                = "example-endpoint"
  location            = azurerm_resource_group.example.location
  resource_group_name = azurerm_resource_group.example.name
  subnet_id           = azurerm_subnet.example.id

  private_service_connection {
    name                           = "example-privateserviceconnection"
    private_connection_resource_id = azurerm_storage_account.example.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  lifecycle {
    ignore_changes = [
      # Ignore changes to private_dns_zone_group, e.g. because an Azure Policy
      # updates it automatically.
      private_dns_zone_group,
    ]
  }
}
```

### AzAPI Terraform provider (using `azapi_update_resource`)

If you are using the [AzAPI Terraform Provider](https://learn.microsoft.com/en-us/azure/developer/terraform/overview), specifically the [azapi_update_resource](https://registry.terraform.io/providers/azure/azapi/latest/docs/resources/update_resource) resource, be aware of the following limitation:

!!! quote "Unchanged properties"
    When you delete an `azapi_update_resource`, **no operation will be performed**, and these properties will stay **unchanged**. If you want to restore the modified properties to some values, you must apply the restored properties **before deleting**.

This means, changes to the `azapi_update_resource` resource may _appear_ to apply changes (ie. remove properties/configurations previous added according to the `terraform plan` output), but this doesn't actually apply those changes in Azure.

## GitHub Actions

If you are using GitHub Actions for your CI/CD pipeline, consider the following best practices:

- Configure [OpenID Connect (OIDC) authentication](#configuring-github-action-oidc-authentication-to-azure) for GitHub Actions to authenticate with Azure.

- If using [Terraform](https://www.terraform.io/), be aware of the limitations when [creating Subnets](#using-terraform-to-create-subnets), and the use of the [AzAPI Terraform Provider](#azapi-terraform-provider-using-azapi_update_resource).

- [Self-hosted runners](#github-self-hosted-runners-on-azure) on Azure are required to access data storage and database services from GitHub Actions. Public access to these services is not supported.

### Configuring GitHub Action OIDC authentication to Azure

To allow GitHub Actions to securely access Azure subscriptions, use OpenID Connect (OIDC) authentication.

For detailed instructions, see the [GitHub Actions OIDC Authentication Guide](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-azure).

Here's a quick summary on how to set it up:

1. The GitHub Identity Provider has already been configured in the Azure subscriptions in your Project Set
2. In your Azure subscription:

  - Create an Entra ID Application and a Service Principal
  - Add federated credentials for the Entra ID Application
  - Create GitHub secrets for storing Azure configuration

3. In your GitHub workflows:

  - Add permissions settings for the token
  - Use the [azure/login](https://github.com/Azure/login) action to exchange the OIDC token (JWT) for a cloud access token

This allows GitHub Actions to authenticate to Azure and access resources.

### GitHub self-hosted runners on Azure

Microsoft has created an [Azure Verified Module (AVM) for CICD Agents and Runners](https://github.com/Azure/terraform-azurerm-avm-ptn-cicd-agents-and-runners). The Public cloud team has tested this module, and verified that it works within our Azure environment (with a few customizations).

We have created a dedicated/centralized GitHub repository to provide sample Terraform code for creating various application patterns, and various tools. This repository is called [Azure Landing Zone Samples (azure-lz-samples)](https://github.com/bcgov/azure-lz-samples).

You can find the sample Terraform code for deploying self-hosted GitHub runners in the `/tools/cicd_self_hosted_agents/` directory.

!!! info "Pre-requisites"
    Please take special note of the pre-requisites listed in the README file in the `/tools/cicd_self_hosted_agents/` directory. It describes the necessary subnets that the self-hosted runners need to be deployed in.

## Azure pipelines

If you are using Azure Pipelines for your CI/CD pipeline, consider the following best practices:

- Configure [Azure DevOps Workload identity federation (OIDC) with Terraform](https://devblogs.microsoft.com/devops/introduction-to-azure-devops-workload-identity-federation-oidc-with-terraform/) for Azure Pipelines to authenticate with Azure.

### Managed DevOps Pools on Azure

Microsoft has created an [Azure Verified Module for Managed DevOps Pools](https://github.com/Azure/terraform-azurerm-avm-res-devopsinfrastructure-pool). The Public cloud team has tested this module, and verified that it works within our Azure environment.

We have created a dedicated/centralized GitHub repository to provide sample Terraform code for creating various application patterns, and various tools. This repository is called [Azure Landing Zone Samples (azure-lz-samples)](https://github.com/bcgov/azure-lz-samples).

You can find the sample Terraform code for deploying DevOps Managed Pools in the `/tools/cicd_managed_devops_pools/` directory.

!!! info "Pre-requisites"
    Please take special note of the pre-requisites listed in the README file in the `/tools/cicd_managed_devops_pools/` directory. It describes the necessary resources, and Resource Providers that are required.