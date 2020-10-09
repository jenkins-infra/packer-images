# packer-images

A repository containing a number of packer build configurations for AWS & Azure.

## Invoking the Azure builds locally

Create a new resource group

```
az group create -n myResourceGroup -l eastus
```

Get your subscription id

```
az account show --query id -o tsv
```

Invoke the build

```
CLOUD=azure AGENT=windows-2019 ARCHITECTURE=amd64 LOCATION=eastus RESOURCE_GROUP_NAME=myResourceGroup AZURE_SUBSCRIPTION_ID=<subscription_id> ./build.sh
```

