#!/bin/bash
set -e

echo "🚀 Installation de Minikube et Kubectl..."

# 1. Téléchargement et installation de Minikube
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube_latest_amd64.deb
sudo dpkg -i minikube_latest_amd64.deb
rm minikube_latest_amd64.deb

# 2. Installation de kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
rm kubectl

# 3. Lancement
echo "🛠️ Démarrage du cluster..."
minikube start --driver=docker

echo "✅ Terminé ! Vérification :"
minikube status
