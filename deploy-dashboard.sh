#!/bin/bash

set -euo pipefail


kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.7.0/aio/deploy/recommended.yaml

kubectl apply -f ./dashboard-rbac.yaml
