#!/bin/bash
# --- Configuration (Uses environment variables with defaults) ---
ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"
ARGOCD_SERVICE="${ARGOCD_SERVICE:-argocd-server}"
ARGOCD_LOCAL_PORT="${ARGOCD_LOCAL_PORT:-8080}"
ARGOCD_REMOTE_PORT="${ARGOCD_REMOTE_PORT:-443}"

TEKTON_NAMESPACE="${TEKTON_DASHBOARD_NAMESPACE:-tekton-pipelines}"
TEKTON_SERVICE="${TEKTON_DASHBOARD_SERVICE:-tekton-dashboard}"
TEKTON_LOCAL_PORT="${TEKTON_DASHBOARD_LOCAL_PORT:-9097}"
TEKTON_REMOTE_PORT="${TEKTON_DASHBOARD_REMOTE_PORT:-9097}"

LISTENER_NAMESPACE="${PIPELINES_NAMESPACE:-ci-pipelines}"
LISTENER_SERVICE="${GITHUB_LISTENER_SERVICE:-el-github-listener}"
LISTENER_LOCAL_PORT="${GITHUB_LISTENER_LOCAL_PORT:-8888}"
LISTENER_REMOTE_PORT="${GITHUB_LISTENER_REMOTE_PORT:-8080}"

# Variables to hold Process IDs (PIDs)
argocd_pid=""
tekton_pid=""
listener_pid=""

# --- Cleanup Function ---
cleanup() {
    echo "" # Add a newline after ^C
    echo "Stopping port forwarding..."
    if [[ -n "$argocd_pid" ]] && kill -0 "$argocd_pid" 2>/dev/null; then
        echo "  Stopping Argo CD forward (PID: $argocd_pid)..."
        kill "$argocd_pid"
    fi
    if [[ -n "$tekton_pid" ]] && kill -0 "$tekton_pid" 2>/dev/null; then
        echo "  Stopping Tekton Dashboard forward (PID: $tekton_pid)..."
        kill "$tekton_pid"
    fi
    if [[ -n "$listener_pid" ]] && kill -0 "$listener_pid" 2>/dev/null; then
        echo "  Stopping GitHub Listener forward (PID: $listener_pid)..."
        kill "$listener_pid"
    fi
    echo "Port forwarding stopped."
}

# --- Main Port Forwarding Function ---
port_forward_services() {
    trap cleanup EXIT SIGINT SIGTERM

    echo "Starting port forwarding setup..."
    local processes_started=0

    # 1. Argo CD Port Forward
    if kubectl wait deployment --for=condition=Available "$ARGOCD_SERVICE" -n "$ARGOCD_NAMESPACE"  --timeout=2m >/dev/null 2>&1; then
        kubectl port-forward --address 0.0.0.0 -n "$ARGOCD_NAMESPACE" "service/$ARGOCD_SERVICE" "$ARGOCD_LOCAL_PORT:$ARGOCD_REMOTE_PORT" >/dev/null 2>&1 &
        argocd_pid=$! # Capture the PID
        if [[ -n "$argocd_pid" ]]; then
             echo "    Argo CD forward started on PORT: $ARGOCD_LOCAL_PORT"
             processes_started=$((processes_started + 1))
        else
             echo "    Error: Failed to start Argo CD port-forward or capture PID."
        fi
    else
        echo "    Error: Timeout or failure waiting for Argo CD deployment '$ARGOCD_SERVICE'. Skipping."
    fi

    # 2. Tekton Dashboard Port Forward
    if kubectl wait deployment --for=condition=Available "$TEKTON_SERVICE" -n "$TEKTON_NAMESPACE"  --timeout=2m >/dev/null 2>&1; then
        kubectl port-forward --address 0.0.0.0 -n "$TEKTON_NAMESPACE" "service/$TEKTON_SERVICE" "$TEKTON_LOCAL_PORT:$TEKTON_REMOTE_PORT" >/dev/null 2>&1 &
        tekton_pid=$!
        if [[ -n "$tekton_pid" ]]; then
            echo "    Tekton Dashboard forward started on PORT: $TEKTON_LOCAL_PORT"
            processes_started=$((processes_started + 1))
        else
            echo "    Error: Failed to start Tekton Dashboard port-forward or capture PID."
        fi
    else
        echo "    Error: Timeout or failure waiting for Tekton Dashboard deployment '$TEKTON_SERVICE'. Skipping."
    fi

    # 3. GitHub Listener Port Forward
    if kubectl wait deployment --for=condition=Available "$LISTENER_SERVICE" -n "$LISTENER_NAMESPACE"  --timeout=2m >/dev/null 2>&1; then
        kubectl port-forward --address 0.0.0.0 -n "$LISTENER_NAMESPACE" "service/$LISTENER_SERVICE" "$LISTENER_LOCAL_PORT:$LISTENER_REMOTE_PORT" >/dev/null 2>&1 &
        listener_pid=$!
        if [[ -n "$listener_pid" ]]; then
            echo "    GitHub Listener forward started on PORT: $LISTENER_LOCAL_PORT"
            processes_started=$((processes_started + 1))
        else
            echo "    Error: Failed to start GitHub Listener port-forward or capture PID."
        fi
    else
        echo "    Error: Timeout or failure waiting for GitHub Listener deployment '$LISTENER_SERVICE'. Skipping."
    fi

    # Check if any processes were actually started
    if [[ "$processes_started" -eq 0 ]]; then
        echo ""
        echo "Error: No port-forward processes could be started."
        exit 1
    fi

    echo ""
    echo "-----------------------------------------------------"
    echo "Port forwarding initiated for $processes_started service(s)."
    echo "  PIDs -> ArgoCD: ${argocd_pid:-N/A}, Tekton: ${tekton_pid:-N/A}, Listener: ${listener_pid:-N/A}"
    echo "  PORTS -> ArgoCD: ${ARGOCD_LOCAL_PORT:-N/A}, Tekton: ${TEKTON_LOCAL_PORT:-N/A}, Listener: ${LISTENER_LOCAL_PORT:-N/A}"
    echo "  Press Ctrl+C to stop."
    echo "-----------------------------------------------------"
    echo ""

    # Wait for all background jobs associated with this script to complete.
    # The script will stay here until Ctrl+C is pressed (triggering the trap)
    # or until all background kubectl processes terminate for some other reason.
    wait
}

# --- Example Usage ---
# Make sure environment variables like ARGOCD_NAMESPACE etc. are set if needed.
# Then, call the function:

# port_forward_services

