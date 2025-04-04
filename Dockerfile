# --- MODIFIED: Use an official NVIDIA CUDA base image ---
# Choose a version compatible with your host driver (565.77 supports CUDA 12.x)
# Ubuntu 22.04 base is compatible with apt commands used below.
FROM nvidia/cuda:12.1.1-base-ubuntu22.04

# Set build arguments (keep relevant ones)
ARG APP_HOME=/app
ARG GITHUB_REPO=https://github.com/unclecode/crawl4ai.git
ARG GITHUB_BRANCH=main
ARG USE_LOCAL=true # Assuming local build context

ENV PYTHONFAULTHANDLER=1 \
    PYTHONHASHSEED=random \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_DEFAULT_TIMEOUT=100 \
    DEBIAN_FRONTEND=noninteractive \
    REDIS_HOST=localhost \
    REDIS_PORT=6379 \
    # Set expected Python version
    PYTHON_VERSION=3.10

# Build arguments needed later in the file
ARG INSTALL_TYPE=all # Default to 'all' for GPU builds unless overridden
ARG ENABLE_GPU=true # Assuming GPU build based on context
ARG TARGETARCH # Docker injects this automatically

LABEL maintainer="unclecode"
LABEL description="🔥🕷️ Crawl4AI: Open-source LLM Friendly Web Crawler & scraper"
LABEL version="1.0"

# --- MODIFIED: Install Python 3.10 and base dependencies ---
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Python 3.10 and related tools
    python3.10 \
    python3-pip \
    python3.10-venv \
    python3-setuptools \
    python3.10-dev \
    # Original base dependencies
    build-essential \
    curl \
    wget \
    gnupg \
    git \
    cmake \
    pkg-config \
    libjpeg-dev \
    redis-server \
    supervisor \
    # Set python3.10 as default python3 and pip3 as default pip
    && update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.10 1 \
    && update-alternatives --install /usr/bin/pip pip /usr/bin/pip3 1 \
    && rm -rf /var/lib/apt/lists/*

# Install libraries needed for Playwright/browser automation (kept from original)
RUN apt-get update && apt-get install -y --no-install-recommends \
    libglib2.0-0 \
    libnss3 \
    libnspr4 \
    libatk1.0-0 \
    libatk-bridge2.0-0 \
    libcups2 \
    libdrm2 \
    libdbus-1-3 \
    libxcb1 \
    libxkbcommon0 \
    libx11-6 \
    libxcomposite1 \
    libxdamage1 \
    libxext6 \
    libxfixes3 \
    libxrandr2 \
    libgbm1 \
    libpango-1.0-0 \
    libcairo2 \
    libasound2 \
    libatspi2.0-0 \
    && rm -rf /var/lib/apt/lists/*

# --- REMOVED: CUDA Toolkit Installation ---
# The nvidia/cuda base image already includes the toolkit.

# Keep platform-specific optimizations (kept from original)
RUN if [ "$TARGETARCH" = "arm64" ]; then \
    echo "🦾 Installing ARM-specific optimizations"; \
    apt-get update && apt-get install -y --no-install-recommends \
    libopenblas-dev \
    && rm -rf /var/lib/apt/lists/*; \
elif [ "$TARGETARCH" = "amd64" ]; then \
    echo "🖥️ Installing AMD64-specific optimizations"; \
    apt-get update && apt-get install -y --no-install-recommends \
    libomp-dev \
    && rm -rf /var/lib/apt/lists/*; \
else \
    echo "Skipping platform-specific optimizations (unsupported platform)"; \
fi

WORKDIR ${APP_HOME}

# Keep the installation script logic (might be simplified later if needed)
RUN echo '#!/bin/bash\n\
if [ "$USE_LOCAL" = "true" ]; then\n\
    echo "📦 Installing from local source..."\n\
    # --- FIXED: Use absolute path for pip --- \n\
    /usr/bin/pip install --no-cache-dir /tmp/project/\n\
else\n\
    echo "🌐 Installing from GitHub..."\n\
    for i in {1..3}; do \n\
        git clone --branch ${GITHUB_BRANCH} ${GITHUB_REPO} /tmp/crawl4ai && break || \n\
        { echo "Attempt $i/3 failed! Taking a short break... ☕"; sleep 5; }; \n\
    done\n\
    # --- FIXED: Use absolute path for pip --- \n\
    /usr/bin/pip install --no-cache-dir /tmp/crawl4ai\n\
fi' > /tmp/install.sh && chmod +x /tmp/install.sh

# Copy local code context for installation
COPY . /tmp/project/

# Copy config files
COPY deploy/docker/supervisord.conf .
COPY deploy/docker/requirements.txt .

# Install base Python requirements
# --- FIXED: Use absolute path for pip ---
RUN /usr/bin/pip install --no-cache-dir -r requirements.txt

# Install optional ML dependencies based on INSTALL_TYPE (defaulting to 'all' for GPU)
# --- FIXED: Using absolute paths for python/pip to avoid PATH issues ---
RUN if [ "$INSTALL_TYPE" = "all" ] ; then \
        echo "Installing 'all' dependencies (including torch, transformers)..." && \
        /usr/bin/pip install --no-cache-dir \
            torch \
            torchvision \
            torchaudio \
            scikit-learn \
            nltk \
            transformers \
            tokenizers && \
        /usr/bin/python3 -m nltk.downloader punkt stopwords ; \
    fi

# Install crawl4ai itself with extras based on INSTALL_TYPE
# --- FIXED: Using absolute paths for python/pip ---
RUN if [ "$INSTALL_TYPE" = "all" ] ; then \
        /usr/bin/pip install "/tmp/project/[all]" && \
        /usr/bin/python3 -m crawl4ai.model_loader ; \
    elif [ "$INSTALL_TYPE" = "torch" ] ; then \
        /usr/bin/pip install "/tmp/project/[torch]" ; \
    elif [ "$INSTALL_TYPE" = "transformer" ] ; then \
        /usr/bin/pip install "/tmp/project/[transformer]" && \
        /usr/bin/python3 -m crawl4ai.model_loader ; \
    else \
        /usr/bin/pip install "/tmp/project" ; \
    fi

# Final pip upgrade, run install script, and checks
# --- FIXED: Using absolute paths for python/pip ---
RUN /usr/bin/pip install --no-cache-dir --upgrade pip && \
    /tmp/install.sh && \
    /usr/bin/python3 -c "import crawl4ai; print('✅ crawl4ai is ready to rock!')" && \
    /usr/bin/python3 -c "from playwright.sync_api import sync_playwright; print('✅ Playwright is feeling dramatic!')"

# Install Playwright browser dependencies
RUN playwright install --with-deps chromium

# Copy remaining docker deployment files
COPY deploy/docker/* ${APP_HOME}/

# Keep original healthcheck
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD bash -c '\
    MEM=$(free -m | awk "/^Mem:/{print \$2}"); \
    if [ $MEM -lt 2048 ]; then \
        echo "⚠️ Warning: Less than 2GB RAM available! Your container might need a memory boost! 🚀"; \
        exit 1; \
    fi && \
    redis-cli ping > /dev/null && \
    curl -f http://localhost:8000/health || exit 1'

# Expose Redis port (run by supervisord)
EXPOSE 6379
# Keep original CMD
CMD ["supervisord", "-c", "supervisord.conf"]
