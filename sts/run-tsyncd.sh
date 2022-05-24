#!/bin/bash

HELM="$(pwd)/linux-amd64/helm"

$HELM repo add silicom https://silicom-ltd.github.io/STS_HELMCharts/
$HELM repo update
$HELM install silicom/sts-silicom --generate-name
