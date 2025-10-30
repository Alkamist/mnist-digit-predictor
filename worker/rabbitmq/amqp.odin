package rabbitmq

import "core:c"

REPLY_SUCCESS :: 200

connection_state_t :: rawptr

status_enum :: enum c.int {
	OK                             = 0x0,
	NO_MEMORY                      = -0x0001,
	BAD_AMQP_DATA                  = -0x0002,
	UNKNOWN_CLASS                  = -0x0003,
	UNKNOWN_METHOD                 = -0x0004,
	HOSTNAME_RESOLUTION_FAILED     = -0x0005,
	INCOMPATIBLE_AMQP_VERSION      = -0x0006,
	CONNECTION_CLOSED              = -0x0007,
	BAD_URL                        = -0x0008,
	SOCKET_ERROR                   = -0x0009,
	INVALID_PARAMETER              = -0x000A,
	TABLE_TOO_BIG                  = -0x000B,
	WRONG_METHOD                   = -0x000C,
	TIMEOUT                        = -0x000D,
	TIMER_FAILURE                  = -0x000E,
	HEARTBEAT_TIMEOUT              = -0x000F,
	UNEXPECTED_STATE               = -0x0010,
	SOCKET_CLOSED                  = -0x0011,
	SOCKET_INUSE                   = -0x0012,
	BROKER_UNSUPPORTED_SASL_METHOD = -0x0013,
	UNSUPPORTED                    = -0x0014,
	_NEXT_VALUE                    = -0x0015,
	TCP_ERROR                      = -0x0100,
	TCP_SOCKETLIB_INIT_ERROR       = -0x0101,
	_TCP_NEXT_VALUE                = -0x0102,
	SSL_ERROR                      = -0x0200,
	SSL_HOSTNAME_VERIFY_FAILED     = -0x0201,
	SSL_PEER_VERIFY_FAILED         = -0x0202,
	SSL_CONNECTION_FAILED          = -0x0203,
	SSL_SET_ENGINE_FAILED          = -0x0204,
	SSL_UNIMPLEMENTED              = -0x0205,
	_SSL_NEXT_VALUE                = -0x0206
}

timeval :: struct {}

socket_t :: struct {}

bytes_t :: struct {
	len:   c.size_t,
	bytes: [^]byte,
}

channel_t :: c.uint16_t

channel_open_ok_t :: struct {
	channel_id: bytes_t,
}

method_number_t :: c.uint32_t

method_t :: struct {
	id:      method_number_t,
	decoded: rawptr,
}

pool_blocklist_t :: struct {
	num_blocks: c.int,
	blocklist:  [^]rawptr,
}

pool_t :: struct {
	pagesize:     c.size_t,
	pages:        pool_blocklist_t,
	large_blocks: pool_blocklist_t,
	next_page:    c.int,
	alloc_block:  cstring,
	alloc_used:   c.size_t,
}

message_t :: struct {
	properties: basic_properties_t,
	body:       bytes_t,
	pool:       pool_t,
}

envelope_t :: struct {
	channel:      channel_t,
	consumer_tag: bytes_t,
	delivery_tag: c.uint64_t,
	redelivered:  boolean_t,
	exchange:     bytes_t,
	routing_key:  bytes_t,
	message:      message_t,
}

response_type_enum :: enum c.int {
	NONE,
	NORMAL,
	LIBRARY_EXCEPTION,
	SERVER_EXCEPTION,
}

rpc_reply_t :: struct {
	reply_type:    response_type_enum,
	reply:         method_t,
	library_error: c.int,
}

sasl_method_enum :: enum c.int {
	UNDEFINED = -1,
	PLAIN     = 0,
	EXTERNAL  = 1,
}

flag_t :: enum c.int {
	CLUSTER_ID = 2,
	APP_ID,
	USER_ID,
	TYPE,
	TIMESTAMP,
	MESSAGE_ID,
	EXPIRATION,
	REPLY_TO,
	CORRELATION_ID,
	PRIORITY,
	DELIVERY_MODE,
	HEADERS,
	CONTENT_ENCODING,
	CONTENT_TYPE,
}

flags_t :: bit_set[flag_t; c.uint32_t]

boolean_t :: c.int

decimal_t :: struct {
	decimals: c.uint8_t,
	value:    c.uint32_t,
}

array_t :: struct {
	num_entries: c.int,
	entries:     [^]field_value_t,
}

field_value_t :: struct {
	kind: c.uint8_t,
	value: struct #raw_union {
		boolean: boolean_t,
		_i8:     c.int8_t,
		_u8:     c.uint8_t,
		_i16:    c.int16_t,
		_u16:    c.uint16_t,
		_i32:    c.int32_t,
		_u32:    c.uint32_t,
		_i64:    c.int64_t,
		_u64:    c.uint64_t,

		_f32:    c.float,
		_f64:    c.double,
		decimal: decimal_t,
		bytes:   bytes_t,

		table: table_t,
		array: array_t,
	},
}

table_entry_t :: struct {
	key:   bytes_t,
	value: field_value_t,
}

table_t :: struct {
	num_entries: c.int,
	entries:     [^]table_entry_t,
}

basic_properties_t :: struct {
	_flags:           flags_t,
	content_type:     bytes_t,
	content_encoding: bytes_t,
	headers:          table_t,
	delivery_mode:    c.uint8_t,
	priority:         c.uint8_t,
	correlation_id:   bytes_t,
	reply_to:         bytes_t,
	expiration:       bytes_t,
	message_id:       bytes_t,
	timestamp:        c.uint64_t,
	type:             bytes_t,
	user_id:          bytes_t,
	app_id:           bytes_t,
	cluster_id:       bytes_t,
}

literal_bytes :: #force_inline proc(str: string) -> bytes_t {
	return {
		len   = len(str),
		bytes = raw_data(str),
	}
}

queue_declare_ok_t :: struct {
	queue:          bytes_t,
	message_count:  c.uint32_t,
	consumer_count: c.uint32_t,
}

basic_consume_ok_t :: struct {
	consumer_tag: bytes_t,
}

when ODIN_OS == .Windows {
	foreign import rabbitmq {
		"librabbitmq.4.lib",
		"system:ws2_32.lib",
        "system:secur32.lib",
        "system:crypt32.lib",
	}
} else when ODIN_OS == .Linux {
	foreign import rabbitmq {
	    "librabbitmq.a",
	    "system:rt",
	    "system:ssl",
	    "system:crypto",
	}
}

@(default_calling_convention="c", link_prefix="amqp_")
foreign rabbitmq {
	new_connection     :: proc() -> connection_state_t ---
	destroy_connection :: proc(state: connection_state_t) -> c.int ---
	connection_close   :: proc(state: connection_state_t, code: c.int) -> rpc_reply_t ---
	socket_open        :: proc(self: ^socket_t, host: cstring, port: c.int) -> status_enum ---
	login              :: proc(state: connection_state_t, vhost: cstring, channel_max, frame_max, heartbeat: c.int, sasl_method: sasl_method_enum, #c_vararg _: ..cstring) -> rpc_reply_t ---
	channel_open       :: proc(state: connection_state_t, channel: channel_t) -> ^channel_open_ok_t ---
	channel_close      :: proc(state: connection_state_t, channel: channel_t, code: c.int) -> rpc_reply_t ---
	queue_declare      :: proc(state: connection_state_t, channel: channel_t, queue: bytes_t, passive, durable, exclusive, auto_delete: boolean_t, arguments: table_t) -> ^queue_declare_ok_t ---
	basic_publish      :: proc(state: connection_state_t, channel: channel_t, exchange, routing_key: bytes_t, mandatory, immediate: boolean_t, properties: ^basic_properties_t, body: bytes_t) -> response_type_enum ---
	basic_consume      :: proc(state: connection_state_t, channel: channel_t, queue, consumer_tag: bytes_t, no_local, no_ack, exclusive: boolean_t, arguments: table_t) -> ^basic_consume_ok_t ---
	consume_message    :: proc(state: connection_state_t, envelope: ^envelope_t, timeout: ^timeval, flags: c.int) -> rpc_reply_t ---
	basic_ack          :: proc(state: connection_state_t, channel: channel_t, delivery_tag: c.uint64_t, multiple: boolean_t) -> c.int ---
	destroy_envelope   :: proc(envelope: ^envelope_t) ---
	get_rpc_reply      :: proc(state: connection_state_t) -> rpc_reply_t ---
	cstring_bytes      :: proc(cstr: cstring) -> bytes_t ---
	tcp_socket_new     :: proc(state: connection_state_t) -> ^socket_t ---
}