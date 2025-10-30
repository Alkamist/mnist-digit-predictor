# ====================== Build stage ======================
FROM ubuntu:latest AS builder

RUN apt-get update && apt-get install -y \
    wget \
    tar \
    clang \
    libssl-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Download and install Odin
RUN wget https://github.com/odin-lang/Odin/releases/download/dev-2025-10/odin-linux-amd64-dev-2025-10-05.tar.gz \
    && tar -xzf odin-linux-amd64-dev-2025-10-05.tar.gz \
    && rm odin-linux-amd64-dev-2025-10-05.tar.gz \
    && mv odin-linux-amd64-nightly+2025-10-05 /opt/odin

ENV PATH="/opt/odin:${PATH}"

# Copy Odin source code
COPY . .

# Build Odin program
RUN odin build . -out:app



# ====================== Runtime stage ======================
FROM ubuntu:latest

# Install runtime dependencies
RUN apt-get update && apt-get install -y \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy the binary from the build stage
COPY --from=builder /app/app .

# Copy the model file
COPY model.json /app/model.json

# Run the binary
CMD ["./app"]