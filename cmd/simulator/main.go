package main

import (
	"context"
	"flag"
	"fmt"
	"log"
	"math/rand"
	"os"
	"sync"
	"time"

	"github.com/cdesiniotis/chord"
	"github.com/cdesiniotis/chord/chordpb"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
)

type SimulatorConfig struct {
	NumNodes       int
	StartPort      int
	BootstrapAddr  string
	BootstrapPort  int
	TestDuration   time.Duration
	LookupInterval time.Duration
	OutputDir      string
	KeySpace       int
}

type NodeInstance struct {
	node    *chord.Node
	nodeID  string
	port    int
	metrics *chord.MetricsCollector
	client  chordpb.ChordClient
	conn    *grpc.ClientConn
}

func main() {
	// Parsear argumentos de línea de comandos
	config := parseFlags()

	fmt.Printf("Iniciando simulador Chord con %d nodos\n", config.NumNodes)
	fmt.Printf("Puerto inicial: %d\n", config.StartPort)
	fmt.Printf("Bootstrap: %s:%d\n", config.BootstrapAddr, config.BootstrapPort)
	fmt.Printf("Duración del test: %v\n", config.TestDuration)
	fmt.Printf("Directorio de salida: %s\n", config.OutputDir)

	// Crear directorio de resultados
	if err := os.MkdirAll(config.OutputDir, 0755); err != nil {
		log.Fatalf("Error creando directorio de resultados: %v", err)
	}

	// Crear nodos
	nodes := make([]*NodeInstance, config.NumNodes)
	var wg sync.WaitGroup

	// Crear el primer nodo (bootstrap)
	nodes[0] = createBootstrapNode(config, 0)
	fmt.Printf("Nodo bootstrap creado en puerto %d\n", nodes[0].port)

	// Esperar un poco para que el bootstrap esté listo
	time.Sleep(2 * time.Second)

	// Crear el resto de nodos y unirlos al ring
	for i := 1; i < config.NumNodes; i++ {
		wg.Add(1)
		go func(index int) {
			defer wg.Done()
			nodes[index] = createAndJoinNode(config, index)
			if nodes[index] != nil {
				fmt.Printf("Nodo %d creado y unido en puerto %d\n", index, nodes[index].port)
			}
		}(i)

		// Agregar un pequeño delay entre creaciones para evitar sobrecarga
		time.Sleep(100 * time.Millisecond)
	}

	wg.Wait()
	fmt.Printf("Todos los %d nodos han sido creados y unidos al ring\n", config.NumNodes)

	// Esperar a que la red se estabilice
	fmt.Println("Esperando estabilización de la red...")
	time.Sleep(10 * time.Second)

	// Actualizar conteo de nodos en métricas
	for _, node := range nodes {
		if node != nil && node.metrics != nil {
			node.metrics.UpdateNodeCount(int64(config.NumNodes))
		}
	}

	// Ejecutar lookups aleatorios
	fmt.Println("Iniciando lookups aleatorios...")
	runRandomLookups(nodes, config)

	// Esperar a que terminen todas las operaciones
	fmt.Println("Finalizando simulación...")
	time.Sleep(5 * time.Second)

	// Cerrar nodos y colectar métricas finales
	cleanupNodes(nodes)

	// Agregar métricas globales
	aggregator := chord.NewGlobalMetricsAggregator(config.OutputDir)
	if err := aggregator.AggregateMetrics(); err != nil {
		log.Printf("Error agregando métricas globales: %v", err)
	}

	fmt.Printf("Simulación completada. Resultados guardados en: %s\n", config.OutputDir)
}

func parseFlags() *SimulatorConfig {
	config := &SimulatorConfig{}

	flag.IntVar(&config.NumNodes, "nodes", 10, "Número de nodos a crear")
	flag.IntVar(&config.StartPort, "start-port", 8000, "Puerto inicial para los nodos")
	flag.StringVar(&config.BootstrapAddr, "bootstrap-addr", "127.0.0.1", "Dirección del nodo bootstrap")
	flag.IntVar(&config.BootstrapPort, "bootstrap-port", 8000, "Puerto del nodo bootstrap")
	flag.DurationVar(&config.TestDuration, "duration", 60*time.Second, "Duración del test")
	flag.DurationVar(&config.LookupInterval, "lookup-interval", 1*time.Second, "Intervalo entre lookups")
	flag.StringVar(&config.OutputDir, "output", "results", "Directorio de salida para resultados")
	flag.IntVar(&config.KeySpace, "keyspace", 1000, "Espacio de claves para lookups aleatorios")

	flag.Parse()
	return config
}

func createBootstrapNode(config *SimulatorConfig, index int) *NodeInstance {
	port := config.StartPort + index
	nodeID := fmt.Sprintf("node_%d_%s_%d", index, "127.0.0.1", port)

	// Crear configuración del nodo
	nodeConfig := chord.DefaultConfig("127.0.0.1", port)
	nodeConfig.Logging = false // Reducir logs en simulación

	// Crear colector de métricas
	metrics, err := chord.NewMetricsCollector(nodeID, config.OutputDir)
	if err != nil {
		log.Printf("Error creando colector de métricas para nodo %d: %v", index, err)
		return nil
	}

	// Crear nodo (bootstrap)
	node := chord.CreateChord(nodeConfig)

	// Crear cliente para este nodo
	client, conn := createClient(fmt.Sprintf("127.0.0.1:%d", port))

	return &NodeInstance{
		node:    node,
		nodeID:  nodeID,
		port:    port,
		metrics: metrics,
		client:  client,
		conn:    conn,
	}
}

func createAndJoinNode(config *SimulatorConfig, index int) *NodeInstance {
	port := config.StartPort + index
	nodeID := fmt.Sprintf("node_%d_%s_%d", index, "127.0.0.1", port)

	// Crear configuración del nodo
	nodeConfig := chord.DefaultConfig("127.0.0.1", port)
	nodeConfig.Logging = false // Reducir logs en simulación

	// Crear colector de métricas
	metrics, err := chord.NewMetricsCollector(nodeID, config.OutputDir)
	if err != nil {
		log.Printf("Error creando colector de métricas para nodo %d: %v", index, err)
		return nil
	}

	// Unirse al ring existente
	node, err := chord.JoinChord(nodeConfig, config.BootstrapAddr, config.BootstrapPort)
	if err != nil {
		log.Printf("Error uniendo nodo %d al ring: %v", index, err)
		metrics.Close()
		return nil
	}

	// Crear cliente para este nodo
	client, conn := createClient(fmt.Sprintf("127.0.0.1:%d", port))

	return &NodeInstance{
		node:    node,
		nodeID:  nodeID,
		port:    port,
		metrics: metrics,
		client:  client,
		conn:    conn,
	}
}

func createClient(addr string) (chordpb.ChordClient, *grpc.ClientConn) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	dialOpts := []grpc.DialOption{
		grpc.WithTransportCredentials(insecure.NewCredentials()),
		grpc.WithBlock(),
	}

	conn, err := grpc.DialContext(ctx, addr, dialOpts...)
	if err != nil {
		log.Printf("Error conectando a %s: %v", addr, err)
		return nil, nil
	}

	client := chordpb.NewChordClient(conn)
	return client, conn
}

func runRandomLookups(nodes []*NodeInstance, config *SimulatorConfig) {
	var wg sync.WaitGroup
	endTime := time.Now().Add(config.TestDuration)

	// Ejecutar lookups desde cada nodo
	for _, node := range nodes {
		if node == nil || node.client == nil {
			continue
		}

		wg.Add(1)
		go func(n *NodeInstance) {
			defer wg.Done()

			ticker := time.NewTicker(config.LookupInterval)
			defer ticker.Stop()

			for time.Now().Before(endTime) {
				select {
				case <-ticker.C:
					performRandomLookup(n, config.KeySpace)
				}
			}
		}(node)
	}

	wg.Wait()
}

func performRandomLookup(node *NodeInstance, keySpace int) {
	if node.client == nil || node.metrics == nil {
		return
	}

	// Generar clave aleatoria
	key := fmt.Sprintf("key_%d", rand.Intn(keySpace))

	// Medir tiempo de lookup
	startTime := time.Now()

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	req := &chordpb.Key{Key: key}
	_, err := node.client.Locate(ctx, req)

	latency := float64(time.Since(startTime).Nanoseconds()) / 1e6 // convertir a ms

	if err != nil {
		log.Printf("Error en lookup desde nodo %s: %v", node.nodeID, err)
		return
	}

	// Registrar métricas
	node.metrics.RecordLookup(latency)
	node.metrics.IncrementMessages()
}

func cleanupNodes(nodes []*NodeInstance) {
	var wg sync.WaitGroup

	for _, node := range nodes {
		if node == nil {
			continue
		}

		wg.Add(1)
		go func(n *NodeInstance) {
			defer wg.Done()

			// Cerrar métricas
			if n.metrics != nil {
				n.metrics.Close()
			}

			// Cerrar conexión cliente
			if n.conn != nil {
				n.conn.Close()
			}

			// El nodo se cerrará automáticamente
		}(node)
	}

	wg.Wait()
}

func init() {
	rand.Seed(time.Now().UnixNano())
}
