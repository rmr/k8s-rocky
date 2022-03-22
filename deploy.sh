#!/bin/bash

curl -sL https://get.helm.sh/helm-v3.8.0-linux-amd64.tar.gz -o helm.tar.gz
tar xvf helm.tar.gz
chmod +x linux-amd64/helm

HELM="$(pwd)/linux-amd64/helm"

$HELM repo add silicom https://silicom-ltd.github.io/STS_$HELMCharts/
$HELM repo update
$HELM install silicom/sts-silicom --generate-name
