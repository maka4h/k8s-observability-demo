FROM rust:1.92 as builder
# Enable nightly to support edition2024 features
RUN rustup default nightly
WORKDIR /app

# Copy manifests
COPY Cargo.toml ./
COPY Cargo.lock* ./

# Create a dummy main.rs to cache dependencies
RUN mkdir src && echo "fn main() {}" > src/main.rs

# Build dependencies (this layer will be cached)
RUN cargo build --release
RUN rm src/main.rs

# Copy actual source code
COPY src ./src

# Build the application
RUN touch src/main.rs && cargo build --release

# Runtime stage
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y \
    ca-certificates \
    wget \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy the binary from builder
COPY --from=builder /app/target/release/order-service /app/order-service

# Expose port
EXPOSE 8001

# Set environment
ENV RUST_LOG=info

# Run the application
CMD ["./order-service"]
