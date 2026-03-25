# Dockerfile for simplified setup - CLOUDFLARED, USQUE, X_TUNNEL
FROM alpine:3.20

WORKDIR /

# Copy start script
COPY start.sh ./

# Copy and extract application archive
COPY app/app.tar.gz /tmp/
RUN tar -xzf /tmp/app.tar.gz -C / && \
    rm /tmp/app.tar.gz

# x-tunnel port
EXPOSE 8080

# ssh port
#EXPOSE 22

# Install necessary runtime dependencies
RUN apk update && apk add --no-cache openssl gcompat openssh wget tar gcompat bash && \
    chmod +x start.sh && \
    # Clean up cache
    rm -rf /var/cache/apk/*

CMD ["./start.sh"]
