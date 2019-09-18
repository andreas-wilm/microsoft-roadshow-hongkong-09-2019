#!/bin/bash

# This script is based on the deploy.sh script that comes with Azure Portal ARM templates.
# It deploys a Genomics account, a Blob storage account and installs the msgen client.
#
# Andreas Wilm <andreas.wilm@microsoft.com>
# Copyright (c) 2019 Microsoft Corporation

set -euo pipefail
IFS=$'\n\t'
# -e: immediately exit if any command has a non-zero exit status
# -o: prevents errors in a pipeline from being masked
# IFS new value is less likely to cause confusing bugs when looping arrays or arguments (e.g. $@)

usage() { echo "Usage: $0 -i <subscriptionId> -g <resourceGroupName>" 1>&2; exit 1; }

declare subscriptionId=""
declare resourceGroupName=""
# Initialize parameters specified from command line
while getopts "hi:g:" arg; do
	case "${arg}" in
		i)
			subscriptionId=${OPTARG}
			;;
		g)
			resourceGroupName=${OPTARG}
			;;
		h)
			usage
			exit
		esac
done
shift $((OPTIND-1))

# Prompt for parameters is some required parameters are missing

if [[ -z "$subscriptionId" ]]; then
	echo "Your subscription ID can be looked up with the CLI using: az account show --out json "
	echo "Enter your subscription ID:"
	echo -n ">"
	read subscriptionId
	[[ "${subscriptionId:?}" ]]
fi

if [[ -z "$resourceGroupName" ]]; then
	echo "This script will look for an existing resource group, otherwise a new one will be created "
	echo "You can create new resource groups with the CLI using: az group create "
	echo "Enter a resource group name"
	echo -n ">"
	read resourceGroupName
	[[ "${resourceGroupName:?}" ]]
fi

if [ -z "$subscriptionId" ] || [ -z "$resourceGroupName" ]; then
	echo "ERROR: Either one of subscriptionId, resourceGroupName, deploymentName is empty" 1>&2
	usage
fi


# Login to Azure
az account show 1> /dev/null
if [ $? != 0 ];
then
	az login
fi

# Set the default subscription id
az account set --subscription $subscriptionId

set +e

# Make sure RG exists
az group show --name $resourceGroupName 1> /dev/null
if [ $? != 0 ]; then
	echo "ERROR: Resource group with name" $resourceGroupName "could not be found." 1>&2
	exit 1
fi

# Get region from RG
region=$(az group show --name $resourceGroupName --query location | tr -d '"')
echo "Using region \"$region\" as per resource group \"$resourceGroupName\""
echo

declare randID=$(cat /dev/urandom | tr -dc 'a-z0-9' | fold -w 6 | head -n 1)
declare storageAccountName="hkmsgenstorage$randID"
declare genomicsAccountName="hkmsgen$randID"

deploymentName="MSGenomics"
parametersFilePath="ms-genomics-account/parameters.json"
templateFilePath="ms-genomics-account/template.json"
sed -e "s/@name@/$genomicsAccountName/" -e "s/@region@/$region/" \
	${parametersFilePath}.template > ${parametersFilePath}
echo "Starting deployment of $deploymentName..."
(
	set -x
	az group deployment create --name "$deploymentName" --resource-group "$resourceGroupName" \
		--template-file "$templateFilePath" --parameters "${parametersFilePath}" >/dev/null
)
if [ $? != 0 ]; then
	echo "ERROR: deployment failed" 1>&2
	exit 1
fi
echo "Successfully created Genomics account."
echo "msgenurl=https://${region}.microsoftgenomics.net"
echo "msgenkey: see 'Access Keys' blade at https://ms.portal.azure.com/#blade/HubsExtension/BrowseResourceBlade/resourceType/Microsoft.Genomics%2Faccounts"
echo

deploymentName="StorageAccount"
parametersFilePath="storage-account/parameters.json"
templateFilePath="storage-account/template.json"
sed -e "s/@name@/$storageAccountName/" -e "s/@region@/$region/" \
	${parametersFilePath}.template > ${parametersFilePath}
echo "Starting deployment of $deploymentName..."
(
	set -x
	az group deployment create --name "$deploymentName" --resource-group "$resourceGroupName" \
		--template-file "$templateFilePath" --parameters "${parametersFilePath}" >/dev/null
)
if [ $? != 0 ]; then
	echo "ERROR: deployment failed" 1>&2
	exit 1
fi
echo "Created storage account"
storageKey=$(az storage account keys list --account-name ${storageAccountName} \
	--output table | awk '/key1/ {print $NF}')
echo "strgacc=${storageAccountName}"
echo "strgkey=${storageKey}"
echo "strgurl=https://${storageAccountName}.blob.core.windows.net"
echo

envName="msgen"
echo "Creating conda environment for MS Genomics client (msgen)"
if ! conda info --envs | grep -wq $envName; then 
	conda create -y -n $envName python=2.7 pip
	conda activate $envName
	pip install $envName
	echo "Done"
else
	echo "Environment already exists. Skipping creation..."
fi
echo "To activate run: conda activate $envName"
echo

echo "Bye"


