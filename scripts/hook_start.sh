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
sudo pkill -x "ecofloc" > /dev/null 2>&1 || true
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

# --- 5. Phase 1 : Lancement Sonde Runner ---
echo "📡 [PHASE 1] Activation des sondes sur le Runner (-n Runner.Worker)..."
for conf in cpu ram sd nic gpu; do
   nohup sudo ecofloc --$conf -n "Runner.Worker" -i 100 -t 3600 -f "$RAW_DIR/" > /dev/null 2>&1 &
    echo $! >> "$PID_FILE"
    echo "  [+] Sonde $conf (Runner) lancée (PID EcoFloc: $!)"
done

## --- 6. Phase 2 : Détection Docker (Stratégie dockerd) ---
CD_PATTERN="docker|push|deploy|publish|production|prod|integration|container|docker-build|k8s|kubernetes|containerd"

if [[ "$JOB_NAME" =~ $CD_PATTERN ]]; then
    echo "🏗️ [ANALYSE] Job Docker détecté ($JOB_NAME)."
    echo "📡 Lancement de la surveillance globale via le démon dockerd..."

    # On marque la cible pour le script de stop
    echo "dockerd" > "$CONTAINER_PID_FILE"

    for conf in cpu ram sd nic gpu; do
        # On cible le nom du processus (-n). EcoFloc suivra dockerd et ses enfants.
        nohup sudo ecofloc --$conf -n "dockerd" -i 1000 -t 3600 -f "$RAW_DIR/" > /dev/null 2>&1 &
        echo $! >> "$PID_FILE"
    done

    echo "✅ [SUCCESS] Sondes dockerd actives. Mesure hybride Runner + Docker prête."
fi
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