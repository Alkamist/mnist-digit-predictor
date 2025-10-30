# ====================== Build stage ======================
FROM golang:1.25.3-alpine AS builder

# Set working directory
WORKDIR /app

# Copy source files
COPY . .

# Download dependencies
RUN go mod download

# Build the application
# CGO_ENABLED=0 creates a statically linked binary
# -ldflags="-w -s" strips debug information to reduce binary size
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-w -s" -o main .



# ====================== Runtime stage ======================
FROM alpine:latest

# Install ca-certificates for HTTPS requests
RUN apk --no-cache add ca-certificates

# Create a dedicated group and user
RUN addgroup -S appgroup && adduser -S appuser -G appgroup

# Create the application directory
WORKDIR /app

# Copy the binary from builder stage
COPY --from=builder /app/main .

# Change ownership of the app directory and binary
RUN chown -R appuser:appgroup /app

# Switch to the non-root user
USER appuser

# Expose port
EXPOSE 8080

# Run the binary as 'appuser' from the '/app' directory
CMD ["./main"]