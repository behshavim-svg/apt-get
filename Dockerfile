# =========================================================
# Stage 1: Create a clean sandbox and download packages
# =========================================================
FROM ubuntu:26.04 AS builder

# Set environment variables for non-interactive apt installations
ENV DEBIAN_FRONTEND=noninteractive

# Install base tools required for setting up repositories
RUN apt-get update && apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    apt-utils \
    && rm -rf /var/lib/apt/lists/*

# Set up official Docker upstream repository GPG key and sources list for Ubuntu 26.04 (Resolute)
RUN mkdir -p -m 0755 /etc/apt/keyrings && \
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg && \
    chmod a+r /etc/apt/keyrings/docker.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu resolute stable" > /etc/apt/sources.list.d/docker.list

# Add official GitLab Runner repository
RUN curl -L "https://packages.gitlab.com/install/repositories/runner/gitlab-runner/script.deb.sh" | os=ubuntu dist=noble bash

# Copy the package list
WORKDIR /tmp
COPY packages.txt .

# 1. Update apt repositories
# 2. Download Core Ubuntu metapackages and additional tools
RUN apt-get update && \
    apt-get install --download-only -y \
        ubuntu-server \
        ubuntu-standard \
        linux-image-virtual \
        linux-headers-virtual \
        docker-ce \
        docker-ce-cli \
        containerd.io \
        gitlab-runner && \
    while read -r package; do \
        apt-get install --download-only -y "$package" || echo "Skipping $package"; \
    done < packages.txt

# Create the final repository structure
WORKDIR /opt/offline-repo

# 3. CRITICAL FIX: Download the actual .deb files for ALL packages already installed in the base image (like libc6, systemd)
RUN cp /var/cache/apt/archives/*.deb . && \
    dpkg-query -f '${binary:Package}\n' -W | while read -r pkg; do \
        apt-get download "$pkg" 2>/dev/null || true; \
    done

# 4. Generate indexes
RUN apt-ftparchive packages . > Packages && \
    gzip -9c Packages > Packages.gz && \
    apt-ftparchive release . > Release

# =========================================================
# Stage 2: Create the lightweight web server image
# =========================================================
FROM nginx:alpine

# Copy the generated repository from builder stage to Nginx web root
COPY --from=builder /opt/offline-repo /usr/share/nginx/html/ubuntu

RUN chmod -R 755 /usr/share/nginx/html/ubuntu

# 2. Create a custom Nginx configuration to enable autoindex in a single line
RUN rm /etc/nginx/conf.d/default.conf && \
    echo "server { listen 80; server_name localhost; location / { root /usr/share/nginx/html; autoindex on; autoindex_exact_size off; autoindex_localtime on; } }" > /etc/nginx/conf.d/default.conf

# Expose HTTP port
EXPOSE 80
