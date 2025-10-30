package main

import "core:os"
import "core:log"
import "core:time"
import "core:slice"
import "core:encoding/json"

import amqp "rabbitmq"
import "ml"
import "ml/mlp"

HOST               :: "rabbitmq"
PORT               :: 5672
CHANNEL_ID         :: 1
REQUEST_QUEUE_NAME :: "mnist_requests"

Prediction_Request :: struct {
	image: [MNIST_IMAGE_SIZE]f32,
}

Prediction_Response :: struct {
	digit:         int,
	probabilities: [MNIST_CLASS_COUNT]f32,
}

try_connect :: proc() -> (connection: amqp.connection_state_t, ok: bool) {
	connection = amqp.new_connection()
	defer if !ok {
		amqp.destroy_connection(connection)
	}

	socket := amqp.tcp_socket_new(connection)
	if socket == nil {
		log.error("Failed to create TCP socket")
		return
	}

	status := amqp.socket_open(socket, HOST, PORT)
	if status != .OK {
		log.error("Failed to open TCP socket")
		return
	}

	login_reply := amqp.login(connection, "/", 0, 131072, 0, .PLAIN, "guest", "guest")
	if login_reply.reply_type != .NORMAL {
		log.errorf("Failed to login to RabbitMQ server: %v", login_reply)
		return
	}

	ok = true
	return
}

main :: proc() {
	defer log.info("Consumer shutting down")

	context.logger = log.create_console_logger()

	// Try to connect repeatedly
	connection: amqp.connection_state_t
	connected:  bool
	for !connected {
		connection, connected = try_connect()
		time.sleep(2 * time.Second)
	}
	defer amqp.destroy_connection(connection)

	amqp.channel_open(connection, CHANNEL_ID)
	reply := amqp.get_rpc_reply(connection)
	log.assert(reply.reply_type == .NORMAL, "Failed to open channel")

	// Declare the Request Queue
	request_queue_name := amqp.cstring_bytes(REQUEST_QUEUE_NAME)
	amqp.queue_declare(connection, CHANNEL_ID, request_queue_name, 0, 1, 0, 0, {})
	reply = amqp.get_rpc_reply(connection)
	log.assert(reply.reply_type == .NORMAL, "Failed to declare request queue")

	// Start Consuming from the Request Queue
	amqp.basic_consume(connection, CHANNEL_ID, request_queue_name, {}, 0, 0, 0, {})
	reply = amqp.get_rpc_reply(connection)
	log.assert(reply.reply_type == .NORMAL, "Failed to start consuming")

	log.info("Waiting for MNIST prediction requests")

	ml.init(1024 * 1024)

	model = make_model()
	defer destroy_model(model)

	model_data, model_ok := os.read_entire_file("/model-storage/model.json")
	log.assert(model_ok, "Failed to load model file")

	unmarshal_err := json.unmarshal(model_data, &model)
	log.assert(unmarshal_err == nil, "Failed to unmarshal model data")

	for {
		envelope: amqp.envelope_t

		// Block for a message (timeout set to 0, which means wait indefinitely)
		result := amqp.consume_message(connection, &envelope, nil, 0)

		if result.reply_type == .NORMAL {
			// Process the incoming request
			handle_request(connection, &envelope)

			// Clean up the envelope
			amqp.destroy_envelope(&envelope)

		} else if result.reply_type == .LIBRARY_EXCEPTION {
			// This happens for timeouts if a timeout was set, or other recoverable errors
			time.sleep(100 * time.Millisecond)
		} else {
			log.error("Error consuming message")
			break
		}
	}

	amqp.channel_close(connection, CHANNEL_ID, amqp.REPLY_SUCCESS)
	amqp.connection_close(connection, amqp.REPLY_SUCCESS)
}

handle_request :: proc(connection: amqp.connection_state_t, envelope: ^amqp.envelope_t) {
	message_body := string(envelope.message.body.bytes[:envelope.message.body.len])

	// Extract Request and Properties

	// Check for properties required for RPC
	if .CORRELATION_ID not_in envelope.message.properties._flags {
		log.warn("Received message without Correlation ID. Ignoring")
		// Acknowledge but skip processing if critical data is missing
		amqp.basic_ack(connection, CHANNEL_ID, envelope.delivery_tag, 0)
		return
	}

	if .REPLY_TO not_in envelope.message.properties._flags {
		log.warn("Received message without ReplyTo queue. Cannot respond")
		amqp.basic_ack(connection, CHANNEL_ID, envelope.delivery_tag, 0)
		return
	}

	correlation_id_bytes := envelope.message.properties.correlation_id.bytes
	correlation_id       := string(correlation_id_bytes[:envelope.message.properties.correlation_id.len])

	reply_to := envelope.message.properties.reply_to

	log.infof("Received request. Correlation ID: %s, ReplyTo: %s\n", correlation_id, string(reply_to.bytes[:reply_to.len]))

	// Deserialize the request
	request: Prediction_Request
	if err := json.unmarshal(transmute([]byte)message_body, &request); err != nil {
		log.error("Failed to unmarshal request message body: %v\n", err)
		amqp.basic_ack(connection, CHANNEL_ID, envelope.delivery_tag, 0)
		return
	}

	// Generate response
	prediction, probabilities := predict(model, request.image[:])

	response_data := Prediction_Response{
		digit         = prediction,
		probabilities = probabilities,
	}
	response_bytes, marshal_err := json.marshal(response_data)
	assert(marshal_err == nil, "Failed to marshal response")

	// Acknowledge the message
	amqp.basic_ack(connection, CHANNEL_ID, envelope.delivery_tag, 0)

	// Create properties for the reply message
	properties := amqp.basic_properties_t{
		_flags         = {.CORRELATION_ID},
		correlation_id = {
			len   = uint(len(correlation_id)),
			bytes = raw_data(correlation_id),
		},
	}

	// Publish the response to the ReplyTo queue
	status := amqp.basic_publish(
		connection,
		CHANNEL_ID,
		{},
		reply_to,
		0,
		0,
		&properties,
		amqp.bytes_t{
			len   = uint(len(response_bytes)),
			bytes = raw_data(response_bytes),
		},
	)

	if status == .LIBRARY_EXCEPTION {
		log.error("Error publishing response!")
	} else {
		log.infof("Published response to %s with Correlation ID: %s\n", string(reply_to.bytes[:reply_to.len]), correlation_id)
	}
}

model: Model

MNIST_IMAGE_SIZE  :: 784
MNIST_CLASS_COUNT :: 10

Model :: struct {
	mlp: mlp.Mlp,
	opt: ml.Optimizer,
}

make_model :: proc(allocator := context.allocator) -> (model: Model) {
	model.mlp = mlp.make(MNIST_IMAGE_SIZE, 128, MNIST_CLASS_COUNT, allocator=allocator)
	return
}

destroy_model :: proc(model: Model) {
	mlp.destroy(model.mlp)
}

forward :: proc(model: Model, input: []f32) -> ml.Array {
	return mlp.forward(model.mlp, ml.array(input))
}

predict :: proc(model: Model, input: []f32) -> (prediction: int, probabilities: [10]f32) {
	ml.clear()

	logits              := forward(model, input)
	probabilities_array := ml.softmax(logits)

	copy(probabilities[:], probabilities_array.data)

	prediction = slice.max_index(probabilities[:])

	return
}