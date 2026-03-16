#!/bin/bash

METRICS_DIR="/home/medyassine/GreenDevOps/energy_metrics"
mkdir -p "$METRICS_DIR"
INTERVAL=1000
TIMEOUT=-1

if [ "$#" -lt 2 ]; then
    echo "Usage: $0 <job_name> \"<command>\""
    exit 1
fi

JOB_NAME=$1
COMMAND_TO_RUN=$2

# Nettoyage des anciens fichiers
sudo rm -f "${METRICS_DIR}/ECOFLOC_*"

echo "--- [GREEN-CI] Démarrage du Job : $JOB_NAME ---"

# 1. Lancement de la charge de travail
eval "$COMMAND_TO_RUN" &
APP_PID=$!

# 2. Lancement des sondes - ON GARDE LES LOGS pour l'affichage final
# On stocke la sortie standard dans des fichiers .log temporaires
sudo /opt/ecofloc/ecofloc-cpu.out -p $APP_PID -i $INTERVAL -t $TIMEOUT -f "$METRICS_DIR/" > "${METRICS_DIR}/cpu.log" 2>&1 &
CPU_PID=$!
sudo /opt/ecofloc/ecofloc-ram.out -p $APP_PID -i $INTERVAL -t $TIMEOUT -f "$METRICS_DIR/" > "${METRICS_DIR}/ram.log" 2>&1 &
RAM_PID=$!
sudo /opt/ecofloc/ecofloc-sd.out  -p $APP_PID -i $INTERVAL -t $TIMEOUT -f "$METRICS_DIR/" > "${METRICS_DIR}/sd.log" 2>&1 &
SD_PID=$!
sudo /opt/ecofloc/ecofloc-nic.out -p $APP_PID -i $INTERVAL -t $TIMEOUT -f "$METRICS_DIR/" > "${METRICS_DIR}/nic.log" 2>&1 &
NIC_PID=$!
sudo /opt/ecofloc/ecofloc-gpu.out -p $APP_PID -i $INTERVAL -t $TIMEOUT -f "$METRICS_DIR/" > "${METRICS_DIR}/gpu.log" 2>&1 &
GPU_PID=$!

# 3. Attente
wait $APP_PID
EXIT_CODE=$?

# 4. Arrêt et flush
sleep 3
# On utilise SIGTERM (15) puis SIGINT (2) pour être sûr qu'EcoFloc termine
sudo kill -15 $CPU_PID $RAM_PID $SD_PID $NIC_PID $GPU_PID 2>/dev/null
sleep 2

echo -e "\n--- RÉSULTATS ÉNERGÉTIQUES FINAUX ---"

# 5. Fonction pour extraire le résumé et renommer
process_results() {
    local mod=$1
    local log_file="${METRICS_DIR}/${mod,,}.log"
    
    echo "[$mod]"
    # Affiche les lignes importantes du log dans le terminal
    grep -E "Average Power|Total Energy" "$log_file" | sed 's/\*/ /g' | xargs -I {} echo "  {}"
    
    # Renommage du CSV (on cherche le fichier généré par le PID)
    local csv_source=$(ls ${METRICS_DIR}/ECOFLOC_${mod}_PID_${APP_PID}* 2>/dev/null | head -n 1)
    if [ -n "$csv_source" ]; then
        mv "$csv_source" "${METRICS_DIR}/${JOB_NAME}_${mod,,}.csv"
    fi
    rm -f "$log_file"
}

process_results "CPU"
process_results "RAM"
process_results "SD"
process_results "NIC"
process_results "GPU"

echo -e "-------------------------------------\n"
