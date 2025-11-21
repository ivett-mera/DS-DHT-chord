#!/bin/bash

# 🌍 Script para conectar manualmente al bootstrap por zona y IP externa
# Uso: ./connect-bootstrap.sh [create|join] [zona_opcional]

set -e

# Configuración de IPs y zonas
BOOTSTRAP_IP="34.38.96.126"    # Europa (Bootstrap)
BOOTSTRAP_PORT="8000"

# Detectar IP externa de la VM actual
EXTERNAL_IP=$(curl -s http://checkip.amazonaws.com/ || curl -s http://ipinfo.io/ip)

echo "🔍 IP Externa detectada: $EXTERNAL_IP"

# Función para determinar configuración por zona/IP
get_zone_config() {
    local ip=$1
    
    case $ip in
        "34.38.96.126")  # Europa (Bootstrap)
            ZONE="europe-west1-d"
            REGION="Europa 🇪🇺"
            LOCAL_PORT="8000"
            METRICS_DIR="vm1_bootstrap"
            IS_BOOTSTRAP=true
            ;;
        "35.199.69.216")  # Sudamérica
            ZONE="southamerica-east1-c"
            REGION="Sudamérica 🇧🇷"
            LOCAL_PORT="8001"
            METRICS_DIR="vm2_southamerica"
            IS_BOOTSTRAP=false
            ;;
        "34.58.253.117")  # US Central
            ZONE="us-central1-c"
            REGION="US Central 🇺🇸"
            LOCAL_PORT="8002"
            METRICS_DIR="vm3_uscentral"
            IS_BOOTSTRAP=false
            ;;
        *)
            echo "❌ IP no reconocida: $ip"
            echo "📋 IPs válidas:"
            echo "  - 34.38.96.126 (Europa - Bootstrap)"
            echo "  - 35.199.69.216 (Sudamérica)"
            echo "  - 34.58.253.117 (US Central)"
            exit 1
            ;;
    esac
}

# Función para crear bootstrap
create_bootstrap() {
    echo "🚀 Creando Bootstrap en $REGION ($ZONE)"
    echo "   IP: $EXTERNAL_IP:$LOCAL_PORT"
    
    # Crear directorios necesarios
    mkdir -p results/metrics/$METRICS_DIR results/logs
    
    # Ejecutar servidor bootstrap
    echo "▶️ Ejecutando: ./bin/chord-server create --addr 0.0.0.0 --port $LOCAL_PORT --metrics --metrics-dir results/metrics/$METRICS_DIR"
    
    if [ "$1" = "--background" ]; then
        nohup ./bin/chord-server create --addr 0.0.0.0 --port $LOCAL_PORT \
            --metrics --metrics-dir results/metrics/$METRICS_DIR \
            > results/logs/${METRICS_DIR}.log 2>&1 &
        echo "✅ Bootstrap iniciado en background (PID: $!)"
        echo "📋 Para ver logs: tail -f results/logs/${METRICS_DIR}.log"
    else
        ./bin/chord-server create --addr 0.0.0.0 --port $LOCAL_PORT \
            --metrics --metrics-dir results/metrics/$METRICS_DIR
    fi
}

# Función para unirse al ring
join_ring() {
    echo "🔗 Uniéndose al ring desde $REGION ($ZONE)"
    echo "   Local: $EXTERNAL_IP:$LOCAL_PORT"
    echo "   Bootstrap: $BOOTSTRAP_IP:$BOOTSTRAP_PORT"
    
    # Crear directorios necesarios
    mkdir -p results/metrics/$METRICS_DIR results/logs
    
    # Unirse al ring
    echo "▶️ Ejecutando: ./bin/chord-server join $BOOTSTRAP_IP $BOOTSTRAP_PORT --addr 0.0.0.0 --port $LOCAL_PORT --metrics --metrics-dir results/metrics/$METRICS_DIR"
    
    if [ "$1" = "--background" ]; then
        nohup ./bin/chord-server join $BOOTSTRAP_IP $BOOTSTRAP_PORT \
            --addr 0.0.0.0 --port $LOCAL_PORT \
            --metrics --metrics-dir results/metrics/$METRICS_DIR \
            > results/logs/${METRICS_DIR}.log 2>&1 &
        echo "✅ Nodo iniciado en background (PID: $!)"
        echo "📋 Para ver logs: tail -f results/logs/${METRICS_DIR}.log"
    else
        ./bin/chord-server join $BOOTSTRAP_IP $BOOTSTRAP_PORT \
            --addr 0.0.0.0 --port $LOCAL_PORT \
            --metrics --metrics-dir results/metrics/$METRICS_DIR
    fi
}

# Función para mostrar ayuda
show_help() {
    echo "🌍 Script de Conexión Bootstrap Chord DHT"
    echo ""
    echo "Uso:"
    echo "  $0 create [--background]           # Crear bootstrap"
    echo "  $0 join [--background]             # Unirse al ring"
    echo "  $0 status                          # Ver estado"
    echo "  $0 stop                            # Detener nodos"
    echo ""
    echo "Opciones:"
    echo "  --background    Ejecutar en background"
    echo ""
    echo "Zonas soportadas:"
    echo "  🇪🇺 Europa:     34.38.96.126 (Bootstrap)"
    echo "  🇧🇷 Sudamérica: 35.199.69.216"
    echo "  🇺🇸 US Central: 34.58.253.117"
}

# Función para ver estado
show_status() {
    echo "📊 Estado de nodos Chord:"
    ps aux | grep chord-server | grep -v grep || echo "❌ No hay nodos corriendo"
    
    echo ""
    echo "📁 Archivos de logs disponibles:"
    ls -la results/logs/*.log 2>/dev/null || echo "❌ No hay logs disponibles"
}

# Función para detener nodos
stop_nodes() {
    echo "🛑 Deteniendo nodos Chord..."
    pkill -f chord-server || echo "❌ No hay nodos para detener"
    echo "✅ Nodos detenidos"
}

# Main
case "${1:-help}" in
    "create")
        get_zone_config $EXTERNAL_IP
        if [ "$IS_BOOTSTRAP" = true ]; then
            create_bootstrap $2
        else
            echo "❌ Esta VM ($EXTERNAL_IP) no es el bootstrap."
            echo "💡 El bootstrap debe ejecutarse en: 34.38.96.126 (Europa)"
            exit 1
        fi
        ;;
    "join")
        get_zone_config $EXTERNAL_IP
        if [ "$IS_BOOTSTRAP" = true ]; then
            echo "⚠️  Esta VM es el bootstrap. Usa 'create' en su lugar."
            exit 1
        else
            join_ring $2
        fi
        ;;
    "status")
        show_status
        ;;
    "stop")
        stop_nodes
        ;;
    "help"|*)
        show_help
        ;;
esac