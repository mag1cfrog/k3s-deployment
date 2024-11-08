#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# Function to display ASCII Art Banner
display_banner() {
    echo -e " \033[33;5m    __  _          _        ___                            \033[0m"
    echo -e " \033[33;5m    \ \(_)_ __ ___( )__    / _ \__ _ _ __ __ _  __ _  ___  \033[0m"
    echo -e " \033[33;5m     \ \ | '_ \` _ \/ __|  / /_\/ _\` | '__/ _\` |/ _\` |/ _ \ \033[0m"
    echo -e " \033[33;5m  /\_/ / | | | | | \__ \ / /_\\  (_| | | | (_| | (_| |  __/ \033[0m"
    echo -e " \033[33;5m  \___/|_|_| |_| |_|___/ \____/\__,_|_|  \__,_|\__, |\___| \033[0m"
    echo -e " \033[33;5m                                               |___/       \033[0m"

    echo -e " \033[36;5m         _  _________   ___         _        _ _           \033[0m"
    echo -e " \033[36;5m        | |/ |__ / __| |_ _|_ _  __| |_ __ _| | |          \033[0m"
    echo -e " \033[36;5m        | ' < |_ \__ \  | || ' \(_-|  _/ _\` | | |          \033[0m"
    echo -e " \033[36;5m        |_|\_|___|___/ |___|_||_/__/\__\__,_|_|_|          \033[0m"
    echo -e " \033[36;5m                                                           \033[0m"
    echo -e " \033[32;5m             https://youtube.com/@jims-garage              \033[0m"
    echo -e " \033[32;5m                                                           \033[0m"
}

display_banner

#############################################
# YOU SHOULD ONLY NEED TO EDIT THIS SECTION #
#############################################

# Version of Kube-VIP to deploy
KVVERSION="v0.6.3"

# K3S Version
k3sVersion="v1.26.10+k3s2"

# Detect system architecture
ARCH=$(uname -m)
if [[ "$ARCH" == "x86_64" ]]; then
    ARCH="amd64"
elif [[ "$ARCH" == "aarch64" || "$ARCH" == "arm64" ]]; then
    ARCH="arm64"
else
    echo -e " \033[31;5mUnsupported architecture: $ARCH\033[0m"
    exit 1
fi

# Set the IP address of the single node
master1=$(hostname -I | awk '{print $1}')  # Automatically detected IP

# User of the local machine
user=$(whoami)  # Automatically detected user

# Interface used on the local machine
interface=$(ip route | grep default | awk '{print $5}' | head -n1)  # Select only the first default interface


# Set the virtual IP address (VIP)
vip=192.168.3.50

# Array of master nodes
masters=()  # No additional master nodes

# Array of worker nodes
workers=()  # No worker nodes

# Array of all nodes
all=($master1)

# Array of all nodes minus master1
allnomaster1=()

# Loadbalancer IP range
lbrange=192.168.3.60-192.168.3.80

# SSH certificate name variable
certName=id_rsa

# SSH config file
config_file=~/.ssh/config

#############################################
#            DO NOT EDIT BELOW              #
#############################################
# For testing purposes - in case time is wrong due to VM snapshots
sudo timedatectl set-ntp off
sudo timedatectl set-ntp on

# Since we're deploying locally, SSH key distribution is unnecessary
# However, to maintain script structure, we'll skip SSH steps if only one node exists

if [ ${#all[@]} -eq 1 ]; then
    echo -e " \033[32;5mSingle-node detected. Skipping SSH key distribution and remote configurations.\033[0m"
else
    # Move SSH certs to ~/.ssh and change permissions
    cp /home/$user/{$certName,$certName.pub} /home/$user/.ssh
    chmod 600 /home/$user/.ssh/$certName 
    chmod 644 /home/$user/.ssh/$certName.pub

    # Add SSH keys for all nodes
    for node in "${all[@]}"; do
      ssh-copy-id $user@$node
    done
fi

# Install k3sup to local machine if not already present
if ! command -v k3sup &> /dev/null
then
    echo -e " \033[31;5mk3sup not found, installing\033[0m"
    curl -sLS https://get.k3sup.dev | sh
    # Rename and install k3sup based on architecture
    if [ "$ARCH" == "arm64" ]; then
        if [ -f "k3sup-arm64" ]; then
            sudo install k3sup-arm64 /usr/local/bin/k3sup
            rm k3sup-arm64
            echo -e " \033[32;5mk3sup installed successfully!\033[0m"
        else
            echo -e " \033[31;5mError: k3sup-arm64 was not downloaded correctly.\033[0m"
            exit 1
        fi
    else
        if [ -f "k3sup" ]; then
            sudo install k3sup /usr/local/bin/k3sup
            rm k3sup
            echo -e " \033[32;5mk3sup installed successfully!\033[0m"
        else
            echo -e " \033[31;5mError: k3sup was not downloaded correctly.\033[0m"
            exit 1
        fi
    fi
else
    echo -e " \033[32;5mk3sup already installed\033[0m"
fi

# Install Kubectl if not already present
if ! command -v kubectl &> /dev/null
then
    echo -e " \033[31;5mKubectl not found, installing\033[0m"
    # Download kubectl based on architecture
    kubectl_url="https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/${ARCH}/kubectl"
    curl -LO "$kubectl_url"
    chmod +x kubectl
    sudo install kubectl /usr/local/bin/
    rm kubectl
    echo -e " \033[32;5mKubectl installed successfully!\033[0m"
else
    echo -e " \033[32;5mKubectl already installed\033[0m"
fi

# Check for SSH config file, create if needed, add/change Strict Host Key Checking (don't use in production!)
if [ ${#all[@]} -gt 1 ]; then
    if [ ! -f "$config_file" ]; then
        # Create the file and add the line
        echo "StrictHostKeyChecking no" > "$config_file"
        # Set permissions to read and write only for the owner
        chmod 600 "$config_file"
        echo "File created and line added."
    else
        # Check if the line exists
        if grep -q "^StrictHostKeyChecking" "$config_file"; then
            # Check if the value is not "no"
            if ! grep -q "^StrictHostKeyChecking no" "$config_file"; then
                # Replace the existing line
                sed -i 's/^StrictHostKeyChecking.*/StrictHostKeyChecking no/' "$config_file"
                echo "Line updated."
            else
                echo "Line already set to 'no'."
            fi
        else
                # Add the line to the end of the file
                echo "StrictHostKeyChecking no" >> "$config_file"
                echo "Line added."
        fi
    fi
fi

# Install policycoreutils for each node
if [ ${#all[@]} -gt 1 ]; then
    for newnode in "${all[@]}"; do
      ssh $user@$newnode -i ~/.ssh/$certName sudo apt install policycoreutils -y
      echo -e " \033[32;5mPolicyCoreUtils installed on $newnode!\033[0m"
    done
else
    echo -e " \033[32;5mInstalling PolicyCoreUtils locally...\033[0m"
    sudo apt install policycoreutils -y
    echo -e " \033[32;5mPolicyCoreUtils installed locally!\033[0m"
fi

# Step 1: Bootstrap First k3s Node
mkdir -p ~/.kube
if [ ${#all[@]} -eq 1 ]; then
    echo -e " \033[34;5mInstalling K3s on the single node...\033[0m"
    k3sup install \
      --local \
      --tls-san $vip \
      --k3s-version $k3sVersion \
      --k3s-extra-args "--disable traefik --disable servicelb --flannel-iface=$interface --node-ip=$master1 --node-taint node-role.kubernetes.io/master=true:NoSchedule" \
      --sudo \
      --context k3s-single-node
    echo -e " \033[32;5mSingle Node K3s bootstrapped successfully!\033[0m"
else
    echo -e " \033[34;5mBootstrapping first master node...\033[0m"
    k3sup install \
      --ip $master1 \
      --user $user \
      --tls-san $vip \
      --cluster \
      --k3s-version $k3sVersion \
      --k3s-extra-args "--disable traefik --disable servicelb --flannel-iface=$interface --node-ip=$master1 --node-taint node-role.kubernetes.io/master=true:NoSchedule" \
      --merge \
      --sudo \
      --local-path $HOME/.kube/config \
      --ssh-key $HOME/.ssh/$certName \
      --context k3s-ha
    echo -e " \033[32;5mFirst Node bootstrapped successfully!\033[0m"
fi

# Set up kubeconfig for single node
if [ ${#all[@]} -eq 1 ]; then
    echo -e " \033[34;5mSetting up kubeconfig...\033[0m"
    mkdir -p ~/.kube
    sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
    sudo chown $(id -u):$(id -g) ~/.kube/config
fi

# Step 2: Install Kube-VIP for HA
# Kube-VIP can still be installed on a single node for future-proofing
echo -e " \033[34;5mInstalling Kube-VIP...\033[0m"
kubectl apply -f https://kube-vip.io/manifests/rbac.yaml

# Step 3: Download kube-vip
curl -sO https://raw.githubusercontent.com/JamesTurland/JimsGarage/main/Kubernetes/K3S-Deploy/kube-vip

echo "Interface: $interface"
echo "VIP: $vip"

sed "s|\$interface|$interface|g; s|\$vip|$vip|g" kube-vip > $HOME/kube-vip.yaml

rm kube-vip

# Step 4: Apply kube-vip.yaml
if [ ${#all[@]} -eq 1 ]; then
    echo -e " \033[34;5mApplying kube-vip.yaml locally...\033[0m"
    kubectl apply -f $HOME/kube-vip.yaml
else
    scp -i ~/.ssh/$certName $HOME/kube-vip.yaml $user@$master1:~/kube-vip.yaml
fi

# Step 5: Connect to Master1 and move kube-vip.yaml
if [ ${#all[@]} -gt 1 ]; then
    echo -e " \033[34;5mConfiguring kube-vip on master1...\033[0m"
    ssh $user@$master1 -i ~/.ssh/$certName <<- EOF
      sudo mkdir -p /var/lib/rancher/k3s/server/manifests
      sudo mv kube-vip.yaml /var/lib/rancher/k3s/server/manifests/kube-vip.yaml
EOF
fi

# Step 6: Add new master nodes (servers) & workers
if [ ${#masters[@]} -gt 0 ]; then
    for newnode in "${masters[@]}"; do
      k3sup join \
        --ip $newnode \
        --user $user \
        --sudo \
        --k3s-version $k3sVersion \
        --server \
        --server-ip $master1 \
        --ssh-key $HOME/.ssh/$certName \
        --k3s-extra-args "--disable traefik --disable servicelb --flannel-iface=$interface --node-ip=$newnode --node-taint node-role.kubernetes.io/master=true:NoSchedule" \
        --server-user $user
      echo -e " \033[32;5mMaster node $newnode joined successfully!\033[0m"
    done
fi

# Add workers
if [ ${#workers[@]} -gt 0 ]; then
    for newagent in "${workers[@]}"; do
      k3sup join \
        --ip $newagent \
        --user $user \
        --sudo \
        --k3s-version $k3sVersion \
        --server-ip $master1 \
        --ssh-key $HOME/.ssh/$certName \
        --k3s-extra-args "--node-label \"longhorn=true\" --node-label \"worker=true\""
      echo -e " \033[32;5mAgent node $newagent joined successfully!\033[0m"
    done
fi

# Step 7: Install kube-vip as network LoadBalancer - Install the kube-vip Cloud Provider
kubectl apply -f https://raw.githubusercontent.com/kube-vip/kube-vip-cloud-provider/main/manifest/kube-vip-cloud-controller.yaml

# Step 8: Install Metallb
# kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.12/manifests/namespace.yaml
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.8/config/manifests/metallb-native.yaml



# Step 8.1: Patch MetalLB controller to tolerate master node taint
echo -e " \033[34;5mPatching MetalLB controller deployment with tolerations...\033[0m"
kubectl patch deployment controller -n metallb-system --patch 'spec:
  template:
    spec:
      tolerations:
      - key: "node-role.kubernetes.io/master"
        operator: "Exists"
        effect: "NoSchedule"'

# Step 8.2: Patch MetalLB speaker daemonset to tolerate master node taint
echo -e " \033[34;5mPatching MetalLB speaker daemonset with tolerations...\033[0m"
kubectl patch daemonset speaker -n metallb-system --patch 'spec:
  template:
    spec:
      tolerations:
      - key: "node-role.kubernetes.io/master"
        operator: "Exists"
        effect: "NoSchedule"'

# Step 8.3: Wait for MetalLB's controller deployment to be ready
echo -e " \033[34;5mWaiting for MetalLB's controller deployment to be ready...\033[0m"
kubectl rollout status deployment/controller -n metallb-system --timeout=180s

# Step 8.4: Wait for MetalLB's webhook-service to have endpoints with a timeout
echo -e " \033[34;5mWaiting for MetalLB's webhook-service to have endpoints...\033[0m"
kubectl wait --for=condition=ready endpoints/metallb-webhook-service -n metallb-system --timeout=300s


echo "MetalLB's webhook-service is now available and has endpoints."

# Step 8.5: Download ipAddressPool and configure using lbrange
curl -sO https://raw.githubusercontent.com/JamesTurland/JimsGarage/main/Kubernetes/K3S-Deploy/ipAddressPool

# Export lbrange for envsubst
export lbrange

# Use envsubst to replace placeholders
envsubst < ipAddressPool > "$HOME/ipAddressPool.yaml"

# Verify if envsubst succeeded
if [ $? -ne 0 ]; then
    echo -e " \033[31;5mError: envsubst command failed for ipAddressPool.\033[0m"
    exit 1
fi

# Apply ipAddressPool.yaml and l2Advertisement.yaml
kubectl apply -f "$HOME/ipAddressPool.yaml"
kubectl apply -f https://raw.githubusercontent.com/JamesTurland/JimsGarage/main/Kubernetes/K3S-Deploy/l2Advertisement.yaml

# Clean up temporary files
rm "$HOME/ipAddressPool.yaml"
rm ipAddressPool

# Step 9: Test with Nginx
kubectl apply -f https://raw.githubusercontent.com/inlets/inlets-operator/master/contrib/nginx-sample-deployment.yaml -n default
kubectl expose deployment nginx-1 --port=80 --type=LoadBalancer -n default

echo -e " \033[32;5mWaiting for K3S to sync and LoadBalancer to come online\033[0m"

# Wait until the Nginx pod is Ready
while [[ $(kubectl get pods -l app=nginx -o 'jsonpath={..status.conditions[?(@.type=="Ready")].status}') != "True" ]]; do
   sleep 1
done

# Step 10: Deploy IP Pools and l2Advertisement
kubectl wait --namespace metallb-system \
                --for=condition=ready pod \
                --selector=component=controller \
                --timeout=120s
kubectl apply -f $HOME/ipAddressPool.yaml
kubectl apply -f https://raw.githubusercontent.com/JamesTurland/JimsGarage/main/Kubernetes/K3S-Deploy/l2Advertisement.yaml

# Clean up temporary files
rm $HOME/ipAddressPool.yaml

# Display Cluster Information
kubectl get nodes
kubectl get svc
kubectl get pods --all-namespaces -o wide

echo -e " \033[32;5mHappy Kubing! Access Nginx at EXTERNAL-IP above\033[0m"
