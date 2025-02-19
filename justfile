environment := env('ENVIRONMENT', 'development')
profile := 'monitoring-' + environment

# Show lis of all commands
default:
    @just --list

_create-users-dir:
    mkdir -p users

# TODO: Try to use [working-directory] just version 1.38 https://just.systems/man/en/working-directory.html?highlight=working#working-directory
create-user user group: _create-users-dir
    #!/usr/bin/env bash
    set -euxo pipefail
    cd users
    user="{{ profile }}-{{ user }}"
    openssl genrsa -out ${user}.key 4096
    openssl req -new -key ${user}.key -out ${user}.csr -subj "/CN={{ user }} /O={{ group }}"
    openssl x509 -req -in ${user}.csr -CA ~/.minikube/ca.crt -CAkey ~/.minikube/ca.key -out ${user}.crt -days 3650
    kubectl config set-credentials ${user} --client-certificate="$(pwd)/${user}.crt" --client-key="$(pwd)/${user}.key"
    kubectl config set-context ${user} --user="${user}" --cluster="{{ profile }}"

delete-user user:
    #!/usr/bin/env bash
    set -euxo pipefail
    user="{{ profile }}-{{ user }}"
    kubectl config delete-context ${user}
    kubectl config delete-user ${user}

# Checking if all necessary applications are installed
verify-dependencies:
    @echo "Checking if all dependencies exists..."
    command -v helmfile
    command -v minikube
    command -v docker
    command -v openssl
    @echo "Everything looks ok."

# Initialize helmfile (helm plugins)
init-helmfile:
    helmfile init

# Create k8s cluster and initialize full local environment (with core services)
create-environment: verify-dependencies
    just create-k8s
    just --one create-user bob dev-team
    just --one create-user joe support-team
    just init-helmfile
    just install-tier core

# Create Minikube profile with specific addons
create-k8s: verify-dependencies
    minikube start --profile={{ profile }} --nodes=3  --cni=calico --addons=csi-hostpath-driver --addons=ingress --kubernetes-version=v1.31.0 --cpus 2 --memory 3072

# Delete Minikube profile
destroy-k8s: verify-dependencies
    -just --one delete-user bob 
    -just --one delete-user joe 
    minikube delete --profile={{ profile }}

# Start Minikube
start-k8s: verify-dependencies
    minikube profile list | grep {{ profile }}
    minikube start --profile={{ profile }} 

# Stop Minikube
stop-k8s:
    minikube stop --profile={{ profile }} 

# Show list of services
services:
    minikube service list --profile={{ profile }} 

# Install all releases
install-all:
    helmfile sync --environment={{ environment }}

# Install releases of specific tier
install-tier tier-name helmfile-args='':
    helmfile sync --environment={{ environment }} --selector tier={{ tier-name }} {{ helmfile-args }} --include-transitive-needs

# Install releases of specific app
install-app app-name helmfile-args='':
    helmfile sync --environment={{ environment }} --selector app={{ app-name }} {{ helmfile-args }} --include-transitive-needs

# Show diff for all releases
diff:
    helmfile diff --environment={{ environment }}

# Show diff for specific tier
diff-tier tier-name:
    helmfile diff --environment={{ environment }} --selector tier={{ tier-name }}

# Show diff for specific app
diff-app app-name:
    helmfile diff --environment={{ environment }} --selector app={{ app-name }}

# Test all releases
test:
    helmfile test --environment={{ environment }}

# Test single app
test-app app-name:
    helmfile test --environment={{ environment }} --selector app={{ app-name }}
