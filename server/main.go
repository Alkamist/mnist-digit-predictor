package main

import (
	"os"
	"fmt"
	"log"
	"net/http"
	"time"
	"strconv"
	"context"
	"encoding/json"

	amqp "github.com/rabbitmq/amqp091-go"
)

const (
	mnistImageSize  = 784
	mnistClassCount = 10
)

type PredictionRequest struct {
	Image [mnistImageSize]float32 `json:"image"`
}

type PredictionResponse struct {
	Digit         int                      `json:"digit"`
	Probabilities [mnistClassCount]float32 `json:"probabilities"`
}

type ErrorResponse struct {
	Error   string `json:"error"`
	Message string `json:"message"`
}

const requestQueueName = "mnist_requests"

var (
	connection *amqp.Connection
	channel    *amqp.Channel
)

func getEnv(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}

func getEnvBool(key string, defaultValue bool) bool {
    valueStr := os.Getenv(key)
    if valueStr == "" {
        return defaultValue
    }
    
    value, err := strconv.ParseBool(valueStr)
    if err != nil {
        return defaultValue
    }
    
    return value
}

func main() {
	rabbitUser := getEnv("RABBITMQ_USER", "guest")
	rabbitPass := getEnv("RABBITMQ_PASS", "guest")
	rabbitHost := getEnv("RABBITMQ_HOST", "rabbitmq")
	rabbitPort := getEnv("RABBITMQ_PORT", "5672")

	connectionURL := fmt.Sprintf("amqp://%s:%s@%s:%s/", rabbitUser, rabbitPass, rabbitHost, rabbitPort)

	var err error

	const retryDelay = 2 * time.Second

	i := 0
	for {
		connection, err = amqp.Dial(connectionURL)
		if err == nil {
			log.Println("Connected to RabbitMQ successfully.")
			break
		}

		log.Printf("Failed to connect to RabbitMQ (attempt %d): %v", i + 1, err)
		log.Printf("Retrying in %v...", retryDelay)

		time.Sleep(2 * time.Second)
	}

	log.Println("Connected to RabbitMQ successfully.")

	channel, err = connection.Channel()
	if err != nil {
		connection.Close()
		log.Fatalf("Failed to open a channel: %v", err)
	}

	_, err = channel.QueueDeclare(
		requestQueueName, // name
		true,             // durable
		false,            // delete when unused
		false,            // exclusive
		false,            // no-wait
		nil,              // arguments
	)
	if err != nil {
		channel.Close()
		connection.Close()
		log.Fatalf("Failed to declare a queue: %v", err)
	}
	log.Printf("Declared request queue: %s", requestQueueName)

	defer connection.Close()
	defer channel.Close()

	corsEnabled := getEnvBool("RUN_LOCALLY", false)

	if corsEnabled {
		http.HandleFunc("/health",  enableCORS(healthHandler))
		http.HandleFunc("/predict", enableCORS(predictHandler))
	} else {
		http.HandleFunc("/health",  healthHandler)
		http.HandleFunc("/predict", predictHandler)
	}

	port := ":8080"
	log.Printf("Starting MNIST prediction server on port %s\n", port)
	if err := http.ListenAndServe(port, nil); err != nil {
		log.Fatal(err)
	}
}

func healthHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		sendError(w, http.StatusMethodNotAllowed, "Method not allowed")
		return
	}

	if connection == nil || connection.IsClosed() {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusServiceUnavailable)
		json.NewEncoder(w).Encode(map[string]string{
			"status":  "unhealthy",
			"service": "mnist-predictor",
			"details": "RabbitMQ connection is closed or nil",
		})
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]string{
		"status":  "healthy",
		"service": "mnist-predictor",
	})
}

func predictHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		sendError(w, http.StatusMethodNotAllowed, "Method not allowed")
		return
	}

	var request PredictionRequest
	if err := json.NewDecoder(r.Body).Decode(&request); err != nil {
		sendError(w, http.StatusBadRequest, "Invalid JSON format")
		return
	}

	// Validate image data size
	if len(request.Image) != 784 {
		sendError(w, http.StatusBadRequest, "Image data must have a length of 784")
		return
	}

	// Send to RabbitMQ and wait for response
	response, err := sendRabbitMQRequest(request)
	if err != nil {
		log.Printf("Error during RabbitMQ request/reply: %v", err)
		sendError(w, http.StatusServiceUnavailable, "Prediction service failed to respond")
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	if err := json.NewEncoder(w).Encode(response); err != nil {
		log.Printf("Error encoding response: %v", err)
	}

	log.Printf("Prediction request processed: predicted digit %d", response.Digit)
}

func sendRabbitMQRequest(request PredictionRequest) (*PredictionResponse, error) {
	// Declare a temporary, exclusive, auto-delete queue for the reply
	q, err := channel.QueueDeclare(
		"",    // name: "" generates a unique name for a temporary queue
		false, // durable
		true,  // delete when unused (auto-delete)
		true,  // exclusive (only accessible by this connection)
		false, // no-wait
		nil,   // arguments
	)
	if err != nil {
		return nil, err
	}
	defer channel.QueueDelete(q.Name, false, false, true)

	msgs, err := channel.Consume(
		q.Name, // queue
		"",     // consumer tag (empty means autogenerate)
		true,   // auto-ack
		false,  // exclusive
		false,  // no-local
		false,  // no-wait
		nil,    // args
	)
	if err != nil {
		return nil, err
	}

	// Prepare the message
	body, err := json.Marshal(request)
	if err != nil {
		return nil, err
	}

	// Generate a unique correlation ID for tracking
	corrID := time.Now().Format("20060102150405.000000") // Simple unique ID

	// Publish the request
	err = channel.Publish(
		"",               // exchange (default exchange)
		requestQueueName, // routing key (the request queue)
		false,            // mandatory
		false,            // immediate
		amqp.Publishing{
			ContentType:   "application/json",
			CorrelationId: corrID,
			ReplyTo:       q.Name,
			Body:          body,
		})
	if err != nil {
		return nil, err
	}
	log.Printf("Sent request with Correlation ID: %s to queue: %s", corrID, requestQueueName)

	ctx, cancel := context.WithTimeout(context.Background(), 5 * time.Second)
	defer cancel()

	select {
	case d := <-msgs: // Message received
		// Check if the correlation ID matches (important if using a shared reply_to queue)
		if d.CorrelationId == corrID {
			var response PredictionResponse
			if err := json.Unmarshal(d.Body, &response); err != nil {
				return nil, err
			}
			log.Printf("Received reply for Correlation ID: %s", corrID)
			return &response, nil
		}

		// If Correlation ID doesn't match, we ignore this message and wait for the correct one
		log.Printf("Received message with mismatched Correlation ID: Expected %s, Got %s", corrID, d.CorrelationId)

		return nil, ctx.Err()

	case <-ctx.Done(): // Timeout occurred
		return nil, ctx.Err()
	}
}

func sendError(w http.ResponseWriter, statusCode int, message string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(statusCode)
	json.NewEncoder(w).Encode(ErrorResponse{
		Error:   http.StatusText(statusCode),
		Message: message,
	})
}

func enableCORS(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "POST, GET, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type")

		if r.Method == "OPTIONS" {
			w.WriteHeader(http.StatusOK)
			return
		}
		
		next(w, r)
	}
}