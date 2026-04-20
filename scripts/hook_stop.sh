#!/bash/bin
# ==============================================================================
# hook_stop.sh — V. Finale : Runner.Worker + dockerd + containerd
# ==============================================================================
set +e
exec >> /tmp/runner_hooks.log 2>&1

# --- 1. Contexte ---
REPO_NAME=$(echo "$GITHUB_REPOSITORY" | tr '[:upper:]' '[:lower:]' | tr '/' '_' | tr '-' '_')
COMMIT_ID="${GITHUB_SHA:0:7}"
BRANCH_NAME="$GITHUB_REF_NAME"
PIPELINE_ID="$GITHUB_RUN_ID"
JOB_NAME=$(echo "$GITHUB_JOB" | tr ' ' '_')

P_NAME=$(cat /tmp/ecofloc_pname.tmp 2>/dev/null || echo "Chatbot-LLM")
P_CAT=$(cat /tmp/ecofloc_pcat.tmp 2>/dev/null || echo "IA")
[ "$GITHUB_EVENT_NAME" = "workflow_dispatch" ] && TRIGGER="manual" || TRIGGER="auto"

# --- 2. Chemins ---
BASE_DIR="/home/medyassine/GreenDevOps/jobs_energy/$REPO_NAME"
RAW_DIR="$BASE_DIR/raw_samples"
JOB_METRICS_DIR="$BASE_DIR/granularity"
ML_DIR="$BASE_DIR/global_history"
PIPELINE_DIR="$BASE_DIR/pipelines_total"
mkdir -p "$JOB_METRICS_DIR" "$ML_DIR" "$PIPELINE_DIR"

PID_FILE="/tmp/ecofloc_${PIPELINE_ID}_${JOB_NAME}.pids"
START_TS_FILE="/tmp/ecofloc_${PIPELINE_ID}_${JOB_NAME}_start.ts"

# --- 3. Temporels & Durée ---
TS_LABEL=$(date +%Y-%m-%d_%H:%M:%S)
END_TS=$(date +%s)
DURATION=0
[ -f "$START_TS_FILE" ] && DURATION=$((END_TS - $(cat "$START_TS_FILE")))

# --- 4. Fonctions de Calcul & Audit ---
fadd() { echo "scale=6; ${1:-0} + ${2:-0}" | bc 2>/dev/null || echo "0"; }

parse_audit() {
    local mod=$1
    local total_j=0; local total_w=0; local n_total=0
    # On remplace kubectl par containerd ici aussi
    local targets=("Runner.Worker" "dockerd" "containerd")
    
    for t in "${targets[@]}"; do
        local csv=$(sudo ls "${RAW_DIR}/ECOFLOC_${mod}_COMM_${t}"*.csv 2>/dev/null | head -1)
        if [ -n "$csv" ] && [ -s "$csv" ]; then
            # Extraction robuste avec awk
            read w j n <<< $(sudo awk -F',' '/^[0-9]/ { sum_p+=$3; sum_e+=$4; count++ } END { if (count>0) printf "%.4f %.4f %d", sum_p/count, sum_e, count; else printf "0 0 0"; }' "$csv")
            total_j=$(echo "$total_j + $j" | bc)
            total_w=$(echo "scale=4; $total_w + $w" | bc)
            n_total=$((n_total + n))
            # Detail log avec formatage propre
            [ "$n" -gt 0 ] && printf "    [DETAIL] %-13s (%s) : %.4f J\n" "$t" "$mod" "$j" >&2
        fi
    done
    printf "%.4f %.4f %d" "$total_w" "$total_j" "$n_total"
}

# --- 5. Arrêt et Rapport ---
if [ -f "$PID_FILE" ]; then
    echo "🛑 Arrêt des sondes EcoFloc..."
    while read pid; do sudo kill -2 "$pid" 2>/dev/null; done < "$PID_FILE"
    sleep 3 

    echo "======================================================="
    echo "📊 RAPPORT ÉNERGÉTIQUE DÉTAILLÉ (COMPOSANTS)"
    echo "======================================================="

    for mod in CPU RAM SD NIC GPU; do
        # Mesure Runner
        R_FILE=$(sudo ls ${RAW_DIR}/ECOFLOC_${mod}_COMM_Runner.Worker*.csv 2>/dev/null | head -1)
        R_J=$(sudo awk -F',' '/^[0-9]/ {s+=$4} END {printf "%.4f", s+0}' "$R_FILE" 2>/dev/null || echo "0.0000")
        
        # Mesure Infrastructure (Somme sécurisée de dockerd, minikube, containerd)
        I_J=0
        for i_cmd in dockerd containerd; do
            I_FILE=$(sudo ls ${RAW_DIR}/ECOFLOC_${mod}_COMM_${i_cmd}*.csv 2>/dev/null | head -1)
            if [ -n "$I_FILE" ]; then
                VAL=$(sudo awk -F',' '/^[0-9]/ {s+=$4} END {printf "%.4f", s+0}' "$I_FILE" 2>/dev/null)
                I_J=$(echo "$I_J + $VAL" | bc)
            fi
        done

        TOTAL_MOD=$(echo "$R_J + $I_J" | bc)
        
        # Affichage avec printf pour forcer les zéros (ex: 0.21 et pas .21)
        printf "🔹 %-4s :\n" "$mod"
        printf "   [Host Runner]    : %8.4f J\n" "$R_J"
        printf "   [Infrastructure] : %8.4f J\n" "$I_J"
        printf "   => Total %-4s    : %8.4f J\n" "$mod" "$TOTAL_MOD"
    done

    # --- 6. Agrégation Bases de Données ---
    read cpu_w cpu_j cpu_n <<< $(parse_audit "CPU")
    read ram_w ram_j ram_n <<< $(parse_audit "RAM")
    read sd_w  sd_j  sd_n  <<< $(parse_audit "SD")
    read nic_w nic_j nic_n <<< $(parse_audit "NIC")
    read gpu_w gpu_j gpu_n <<< $(parse_audit "GPU")

    JOB_TOTAL_J=$(fadd $cpu_j $(fadd $ram_j $(fadd $sd_j $(fadd $nic_j $gpu_j))))
    
    # NIVEAU 1 : GRANULARITÉ
    G_HEADER="date,pipeline_id,commit_id,repo_name,project_name,category,branch,trigger,duration_s,avg_power_w,total_energy_j,samples"
    for entry in "cpu:$cpu_w:$cpu_j:$cpu_n" "ram:$ram_w:$ram_j:$ram_n" "sd:$sd_w:$sd_j:$sd_n" "nic:$nic_w:$nic_j:$nic_n" "gpu:$gpu_w:$gpu_j:$gpu_n"; do
        IFS=: read mod pw ej sn <<< "$entry"
        FILE="${JOB_METRICS_DIR}/history_${JOB_NAME}_${mod}.csv"
        [ ! -f "$FILE" ] && echo "$G_HEADER" > "$FILE"
        echo "$TS_LABEL,$PIPELINE_ID,$COMMIT_ID,$REPO_NAME,$P_NAME,$P_CAT,$BRANCH_NAME,$TRIGGER,$DURATION,$pw,$ej,$sn" >> "$FILE"
    done

    # NIVEAU 2 : MASTER DB (JOBS)
    ML_HEADER="date,pipeline_id,commit_id,repo_name,project_name,category,branch,trigger,job_name,duration_s,cpu_j,ram_j,sd_j,nic_j,gpu_j,total_energy_j"
    ML_FILE="${ML_DIR}/master_energy_database.csv"
    [ ! -f "$ML_FILE" ] && echo "$ML_HEADER" > "$ML_FILE"
    echo "$TS_LABEL,$PIPELINE_ID,$COMMIT_ID,$REPO_NAME,$P_NAME,$P_CAT,$BRANCH_NAME,$TRIGGER,$JOB_NAME,$DURATION,$cpu_j,$ram_j,$sd_j,$nic_j,$gpu_j,$JOB_TOTAL_J" >> "$ML_FILE"

    # NIVEAU 3 : PIPELINE TOTAL (UPSERT)
    ACC_FILE="/tmp/pipeline_${PIPELINE_ID}_sum.tmp"
    [ ! -f "$ACC_FILE" ] && echo "0" > "$ACC_FILE"
    CURRENT_SUM=$(cat "$ACC_FILE")
    NEW_SUM=$(fadd $CURRENT_SUM $JOB_TOTAL_J)
    echo "$NEW_SUM" > "$ACC_FILE"

    PIPE_FILE="${PIPELINE_DIR}/pipeline_summary.csv"
    PIPE_HEADER="date,pipeline_id,commit_id,repo_name,project_name,category,branch,trigger,total_pipeline_energy_j"
    
    [ ! -f "$PIPE_FILE" ] && echo "$PIPE_HEADER" > "$PIPE_FILE"
    grep -v -w "$PIPELINE_ID" "$PIPE_FILE" > "${PIPE_FILE}.tmp" || true
    echo "$TS_LABEL,$PIPELINE_ID,$COMMIT_ID,$REPO_NAME,$P_NAME,$P_CAT,$BRANCH_NAME,$TRIGGER,$NEW_SUM" >> "${PIPE_FILE}.tmp"
    mv "${PIPE_FILE}.tmp" "$PIPE_FILE"

    echo "✅ [SUCCESS] Pipeline $PIPELINE_ID mis à jour : $NEW_SUM J"
    echo "🏁 [STOP] Job $JOB_NAME terminé. ($JOB_TOTAL_J J)"

    # Nettoyage
    sudo rm -f "$PID_FILE" "$START_TS_FILE" "/tmp/ecofloc_${PIPELINE_ID}_${JOB_NAME}.cid" "${RAW_DIR}/ECOFLOC_"*.csv
fi