# =========================================================
# Stage 1: Create a clean sandbox and download packages
# =========================================================
FROM ubuntu:24.04 AS builder

# Set environment variables for non-interactive apt installations
ENV DEBIAN_FRONTEND=noninteractive

# Install base tools required for setting up repositories
RUN apt-get update && apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    apt-utils \
    && rm -rf /var/lib/apt/lists/*

# Set up official Docker upstream repository GPG key and sources list
# FIXED: Removed the invalid '-d' option from mkdir
RUN mkdir -p -m 0755 /etc/apt/keyrings && \
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg && \
    chmod a+r /etc/apt/keyrings/docker.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu noble stable" > /etc/apt/sources.list.d/docker.list

# Copy the package list
WORKDIR /tmp
COPY packages.txt .

# 1. Update apt repositories
# 2. Download Kernel updates and Docker CE packages
# 3. Read packages.txt and download every single package listed in it using xargs
# FIXED: Corrected the chaining syntax for xargs and apt-get
RUN apt-get update && \
    apt-get install --download-only -y \
        linux-image-virtual \
        linux-headers-virtual \
        docker-ce \
        docker-ce-cli \
        containerd.io && \
    xargs -a packages.txt apt-get install --download-only -y

# Create the final repository structure and generate indexes
WORKDIR /opt/offline-repo
RUN cp /var/cache/apt/archives/*.deb . && \
    apt-ftparchive packages . > Packages && \
    gzip -9c Packages > Packages.gz && \
    apt-ftparchive release . > Release

# =========================================================
# Stage 2: Create the lightweight web server image
# =========================================================
FROM nginx:alpine

# Copy the generated repository from builder stage to Nginx web root
COPY --from=builder /opt/offline-repo /usr/share/nginx/html/ubuntu

# Expose HTTP port
EXPOSE 80
