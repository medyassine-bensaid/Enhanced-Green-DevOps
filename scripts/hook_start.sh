#!/bin/bash
# ==============================================================================
# hook_start.sh — STRATÉGIE DE MESURE HYBRIDE (RUNNER + DOCKER)
# ==============================================================================
set +e
exec >> /tmp/runner_hooks.log 2>&1
# Nettoyage préventif des vieux fichiers de plus de 1 jour pour éviter l'encombrement
find /tmp -name "ecofloc_*" -mtime +1 -delete 2>/dev/null
find /tmp -name "pipeline_*_sum.tmp" -mtime +1 -delete 2>/dev/null

# --- 1. Variables Dynamiques & Contextuelles ---
REPO_NAME=$(echo "$GITHUB_REPOSITORY" | tr '[:upper:]' '[:lower:]' | tr '/' '_' | tr '-' '_')
JOB_NAME=$(echo "$GITHUB_JOB" | tr '[:upper:]' '[:lower:]' | tr ' ' '_')
PIPELINE_ID="$GITHUB_RUN_ID"
echo "$PROJECT_NAME" > /tmp/ecofloc_pname.tmp
echo "$PROJECT_CATEGORY" > /tmp/ecofloc_pcat.tmp

echo "========================================================================"
echo "🚀 [START] INITIALISATION DU JOB : $GITHUB_JOB"
echo "📅 Date : $(date '+%Y-%m-%d %H:%M:%S')"
echo "🆔 Pipeline ID : $PIPELINE_ID | Repo : $REPO_NAME"
echo "========================================================================"

# --- 2. Arborescence de Stockage ---
BASE_DIR="/home/medyassine/GreenDevOps/jobs_energy/$REPO_NAME"
RAW_DIR="$BASE_DIR/raw_samples"
mkdir -p "$RAW_DIR"
echo "📂 Dossier de sortie : $RAW_DIR"

# --- 3. Purge & Diagnostics ---
sudo pkill -f "ecofloc --cpu" 2>/dev/null || true
sudo pkill -f "ecofloc --ram" 2>/dev/null || true
sudo pkill -f "ecofloc --sd"  2>/dev/null || true
sudo pkill -f "ecofloc --nic" 2>/dev/null || true
sudo pkill -f "ecofloc --gpu" 2>/dev/null || true
sudo pkill -f "nethogs wlp2s0" 2>/dev/null || true
sleep 1

#------
sudo rm -f "$RAW_DIR"/*.csv > /dev/null 2>&1 || true

echo "🔍 [DIAGNOSTIC] Vérification des prérequis système..."
if lsmod | grep -q "msr"; then
    echo "  [OK] Module MSR (Intel RAPL) déjà chargé."
else
    sudo modprobe msr 2>/dev/null && echo "  [OK] Module MSR chargé avec succès." || echo "  [!!] Erreur : Impossible de charger MSR."
fi

set -e
# --- 4. Timer et Fichiers de Tracking ---
TS_FILE="/tmp/ecofloc_${PIPELINE_ID}_${JOB_NAME}_start.ts"
PID_FILE="/tmp/ecofloc_${PIPELINE_ID}_${JOB_NAME}.pids"
CONTAINER_PID_FILE="/tmp/ecofloc_${PIPELINE_ID}_${JOB_NAME}.cid"
echo $(date +%s) > "$TS_FILE"
> "$PID_FILE"
echo "⏱️  Timestamp enregistré dans $TS_FILE"
# --- 5. Lancement des Sondes (Stratégie Dynamique Unifiée) ---

sleep 2

declare -a TARGETS=("Runner.Worker")
CD_PATTERN="docker|push|deploy|publish|production|prod|integration|container|docker-build|k8s|kubernetes|containerd"

# Détection de l'infrastructure
if [[ "$JOB_NAME" =~ $CD_PATTERN ]]; then
    echo "🔍 [DEBUG] Analyse d'infrastructure..."
    # On surveille les démons lourds : Docker, le coeur de Minikube et l'exécuteur de conteneurs
    for cmd in dockerd containerd; do
        # -f pour trouver les processus même si le nom est un chemin complet
        PID=$(pgrep -f "$cmd" | head -n 1)
        if [ -n "$PID" ]; then
            TARGETS+=("$cmd")
            echo "  -> [FOUND] $cmd actif (PID: $PID). Ajouté à l'audit."
        fi
    done
fi

echo "📡 [MONITOR] Activation des sondes (Interval: 500ms)..."
for target in "${TARGETS[@]}"; do
    echo "   [+] Target: $target"
    for conf in cpu ram sd nic gpu; do
        # On utilise 500ms pour équilibrer précision et charge CPU sur le Latitude
        sudo nohup ecofloc --$conf -n "$target" -i 500 -t 3600 -f "$RAW_DIR/" > /dev/null 2>&1 &
        E_PID=$!
        
        # Vérification de survie immédiate
        sleep 0.1
        if ps -p $E_PID > /dev/null; then
            echo $E_PID >> "$PID_FILE"
            echo "      - $conf : OK (PID: $E_PID)"
        else
            echo "      - $conf : ❌ ÉCHEC"
        fi
    done
done
# --- 7. Snapshot Visuel & Audit ---
(
  sleep 6
  echo ""
  echo "------------------------------------------------------------------------"
  echo "📸 [SNAPSHOT AUDIT] État des processus pour $JOB_NAME"
  W_PID=$(pgrep -f "Runner.Worker")
  [ -n "$W_PID" ] && echo "🌳 Arbre du Runner ($W_PID) :" && pstree -ap "$W_PID" 2>/dev/null
  sleep 2
  echo "📊 Processus EcoFloc actifs :"
  pgrep -af "ecofloc" | grep "$RAW_DIR"
) & 
disown

echo "✅ [SUCCESS] Setup terminé. $JOB_NAME est sous haute surveillance."
exit 0