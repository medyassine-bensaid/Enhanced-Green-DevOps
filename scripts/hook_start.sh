#!/bin/bash
# ==============================================================================
# hook_start.sh — Initialisation, Diagnostics et Lancement des Capteurs
# ==============================================================================

# Redirection des logs pour le debug
exec >> /tmp/runner_hooks.log 2>&1

# --- 1. Variables Dynamiques ---
REPO_NAME=$(echo "$GITHUB_REPOSITORY" | tr '[:upper:]' '[:lower:]' | tr '/' '_' | tr '-' '_')
JOB_NAME=$(echo "$GITHUB_JOB" | tr '[:upper:]' '[:lower:]' | tr ' ' '_')
PIPELINE_ID="$GITHUB_RUN_ID"

echo "========================================================================"
echo "🚀 [START] INITIALISATION DU JOB: $GITHUB_JOB"
echo "📅 Date: $(date '+%Y-%m-%d %H:%M:%S')"
echo "🆔 Pipeline ID: $PIPELINE_ID | Repo: $REPO_NAME"
echo "========================================================================"

# --- 2. Arborescence de Stockage ---

BASE_DIR="/home/medyassine/GreenDevOps/jobs_energy/$REPO_NAME"
RAW_DIR="$BASE_DIR/raw_samples"
mkdir -p "$RAW_DIR"

# --- 3. Diagnostics Système ---
echo "🔍 Vérification du système..."
# MSR est nécessaire pour la lecture CPU via Intel RAPL
if lsmod | grep -q "msr"; then
    echo "  [OK] Module MSR déjà chargé."
else
    sudo modprobe msr 2>/dev/null && echo "  [OK] Module MSR chargé avec succès." || echo "  [!!] Erreur: Impossible de charger MSR."
fi

# --- 4. Timer et Fichiers de Tracking ---
TS_FILE="/tmp/ecofloc_${PIPELINE_ID}_${JOB_NAME}_start.ts"
echo $(date +%s) > "$TS_FILE"
echo "⏱️  Timestamp de début enregistré."

# --- 5. Lancement des Sondes EcoFloc ---
PID_FILE="/tmp/ecofloc_${PIPELINE_ID}_${JOB_NAME}.pids"
> "$PID_FILE"
echo "📡 Activation des capteurs (Intervalle: 1000ms)..."

for conf in cpu ram sd nic gpu; do
    # On cible Runner.Worker (le processus qui exécute tes scripts python/docker/lint)
    sudo ecofloc --$conf -n "Runner.Worker" -i 1000 -t 3600 -f "$RAW_DIR/" > /dev/null 2>&1 &
    echo $! >> "$PID_FILE"
    echo "  [+] Sonde $conf active (PID: $!)"
done

# --- 6. Snapshot Visuel (Arrière-plan) ---
(
  sleep 6 # On attend que le job commence ses steps
  echo ""
  echo "---------------------------------------------------"
  echo "📸 [SNAPSHOT] Processus cibles pour $JOB_NAME :"
  WORKER_PID=$(pgrep -f "Runner.Worker")
  if [ -n "$WORKER_PID" ]; then
      pstree -ap "$WORKER_PID" 2>/dev/null
  else
      echo "  [!] Attention: Runner.Worker non détecté. Vérifiez vos permissions."
  fi
  echo "---------------------------------------------------"
  echo ""
) & 

echo "✅ [SUCCESS] Setup terminé. Prêt pour l'exécution."
exit 0