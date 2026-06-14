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

RUN curl -L "https://packages.gitlab.com/install/repositories/runner/gitlab-runner/script.deb.sh"
# Copy the package list
WORKDIR /tmp
COPY packages.txt .

# 1. Update apt repositories
# 2. Download Core Ubuntu 26.04 OS metapackages (this guarantees new dependencies like python3.14 are fetched)
# 3. Download Docker CE packages and Kernel updates
# 4. Iterate through packages.txt. It will naturally fetch the 26.04 versions for unchanged package names (e.g., 'nginx').
#    If a 24.04 specific package name is not found, it gracefully skips it without breaking the build.
RUN apt-get update && \
    apt-get install --download-only -y \
        ubuntu-server \
        ubuntu-standard \
        linux-image-virtual \
        linux-headers-virtual \
        docker-ce \
        docker-ce-cli \
        containerd.io && \
        gitlab-runner && \
    while read -r package; do \
        apt-get install --download-only -y "$package" || echo "Skipping $package: Not found in 26.04 repos, likely replaced or deprecated."; \
    done < packages.txt

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

RUN chmod -R 755 /usr/share/nginx/html/ubuntu

# 2. Create a custom Nginx configuration to enable autoindex in a single line
RUN rm /etc/nginx/conf.d/default.conf && \
    echo "server { listen 80; server_name localhost; location / { root /usr/share/nginx/html; autoindex on; autoindex_exact_size off; autoindex_localtime on; } }" > /etc/nginx/conf.d/default.conf

# Expose HTTP port
EXPOSE 80
