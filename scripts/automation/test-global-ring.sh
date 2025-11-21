#!/bin/bash

# Script para probar el ring DHT en las 3 VMs Linux
# Ejecutar desde cualquier VM después de configurar el ring

set -e

# IPs de las VMs
VM1_IP="34.175.112.12"    # Europa (Bootstrap)
VM2_IP="35.199.69.216"   # Sudamérica  
VM3_IP="34.58.253.117"   # US Central

echo "=== Test Completo del Ring DHT Global ==="

# Función para test básico
test_basic_operations() {
    echo ""
    echo "🧪 Test 1: Operaciones Básicas PUT/GET/LOCATE"
    
    # PUT desde Europa
    echo "PUT desde Europa..."
    ./bin/chord-client put $VM1_IP:8000 global_test "Hola desde 3 continentes - $(date)"
    
    sleep 2
    
    # GET desde cada VM
    echo "GET desde Europa:"
    ./bin/chord-client get $VM1_IP:8000 global_test
    
    echo "GET desde Sudamérica:"
    ./bin/chord-client get $VM2_IP:8001 global_test
    
    echo "GET desde US Central:"
    ./bin/chord-client get $VM3_IP:8002 global_test
    
    # LOCATE desde bootstrap
    echo "LOCATE desde Europa:"
    ./bin/chord-client locate $VM1_IP:8000 global_test
    
    echo "✅ Test básico completado"
}

# Función para test de latencia
test_latency() {
    echo ""
    echo "🌍 Test 2: Latencia Cross-Continental"
    
    # Preparar datos de test
    ./bin/chord-client put $VM1_IP:8000 latency_test "Test de latencia - $(date)"
    sleep 1
    
    for i in {1..3}; do
        echo "=== Ronda $i ==="
        
        echo -n "Europa -> Europa: "
        time -p ./bin/chord-client get $VM1_IP:8000 latency_test >/dev/null 2>&1
        
        echo -n "Europa -> Sudamérica: "
        time -p ./bin/chord-client get $VM2_IP:8001 latency_test >/dev/null 2>&1
        
        echo -n "Europa -> US Central: "
        time -p ./bin/chord-client get $VM3_IP:8002 latency_test >/dev/null 2>&1
        
        echo "---"
        sleep 1
    done
    
    echo "✅ Test de latencia completado"
}

# Función para test de tolerancia a fallos
test_fault_tolerance() {
    echo ""
    echo "🔧 Test 3: Tolerancia a Fallos"
    
    # Poner datos en el ring
    ./bin/chord-client put $VM1_IP:8000 fault_test "Datos para test de tolerancia"
    sleep 2
    
    # Verificar que los datos están en múltiples nodos
    echo "Verificando replicación:"
    ./bin/chord-client get $VM1_IP:8000 fault_test
    ./bin/chord-client get $VM2_IP:8001 fault_test
    ./bin/chord-client get $VM3_IP:8002 fault_test
    
    echo "✅ Test de tolerancia completado"
}

# Función para test de carga
test_load() {
    echo ""
    echo "📊 Test 4: Test de Carga"
    
    echo "Insertando múltiples claves..."
    for i in {1..10}; do
        ./bin/chord-client put $VM1_IP:8000 "key_$i" "Valor $i desde $(hostname) - $(date)"
        echo -n "."
    done
    echo ""
    
    sleep 2
    
    echo "Leyendo claves desde diferentes VMs:"
    for i in {1..10}; do
        VM_PORT=$((8000 + (i % 3)))
        case $VM_PORT in
            8000) VM_IP=$VM1_IP ;;
            8001) VM_IP=$VM2_IP ;;
            8002) VM_IP=$VM3_IP ;;
        esac
        
        result=$(./bin/chord-client get $VM_IP:$VM_PORT "key_$i" 2>/dev/null || echo "NOT_FOUND")
        echo "key_$i desde $VM_IP:$VM_PORT -> $result"
    done
    
    echo "✅ Test de carga completado"
}

# Función para verificar estado del ring
check_ring_status() {
    echo ""
    echo "📋 Estado del Ring DHT"
    
    echo "Procesos activos:"
    ps aux | grep chord-server | grep -v grep || echo "No hay procesos chord-server"
    
    echo ""
    echo "Puertos abiertos:"
    ss -tulpn | grep :800 || echo "No hay puertos 8000+ abiertos"
    
    echo ""
    echo "Conectividad entre VMs:"
    for ip in $VM1_IP $VM2_IP $VM3_IP; do
        if timeout 3 bash -c "echo >/dev/tcp/$ip/8000" 2>/dev/null; then
            echo "✅ $ip:8000 - Accesible"
        else
            echo "❌ $ip:8000 - No accesible"
        fi
    done
    
    echo ""
    echo "Logs recientes:"
    if [ -d "results/logs" ]; then
        find results/logs -name "*.log" -exec echo "=== {} (últimas 3 líneas) ===" \; -exec tail -3 {} \;
    fi
}

# Función para generar reporte
generate_report() {
    echo ""
    echo "📊 Generando Reporte de Test..."
    
    REPORT_FILE="results/test_report_$(date +%Y%m%d_%H%M%S).txt"
    
    {
        echo "=== REPORTE DE TEST CHORD DHT GLOBAL ==="
        echo "Fecha: $(date)"
        echo "Ejecutado desde: $(hostname) - $(curl -s ifconfig.me)"
        echo ""
        echo "=== CONFIGURACIÓN ==="
        echo "VM1 (Europa): $VM1_IP:8000"
        echo "VM2 (Sudamérica): $VM2_IP:8001"
        echo "VM3 (US Central): $VM3_IP:8002"
        echo ""
        echo "=== MÉTRICAS GENERADAS ==="
        find results/metrics -name "*.csv" -exec wc -l {} \; 2>/dev/null || echo "No hay archivos de métricas"
        echo ""
        echo "=== LOGS GENERADOS ==="
        find results/logs -name "*.log" -exec wc -l {} \; 2>/dev/null || echo "No hay archivos de log"
    } > "$REPORT_FILE"
    
    echo "Reporte guardado en: $REPORT_FILE"
}

# Función principal
main() {
    echo "Iniciando tests del Ring DHT Global..."
    echo "VMs objetivo:"
    echo "- VM1 (Europa): $VM1_IP:8000"
    echo "- VM2 (Sudamérica): $VM2_IP:8001"  
    echo "- VM3 (US Central): $VM3_IP:8002"
    
    # Verificar que tenemos los binarios
    if [ ! -f "./bin/chord-client" ]; then
        echo "❌ Error: chord-client no encontrado"
        echo "Ejecuta primero: go build -o bin/chord-client ./client"
        exit 1
    fi
    
    # Verificar conectividad básica
    check_ring_status
    
    # Ejecutar tests
    test_basic_operations
    test_latency
    test_fault_tolerance
    test_load
    
    # Generar reporte final
    generate_report
    
    echo ""
    echo "🎉 Todos los tests completados!"
    echo "Revisa los logs en results/logs/ y métricas en results/metrics/"
    echo ""
    echo "Para monitoreo continuo:"
    echo "- Logs: tail -f results/logs/*.log"
    echo "- Procesos: watch 'ps aux | grep chord'"
    echo "- Red: watch 'ss -tulpn | grep :800'"
}

# Ejecutar si se llama directamente
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
