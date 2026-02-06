# Use the official Python image as a base image
FROM mcr.microsoft.com/devcontainers/python:3.12-bookworm

# Fix broken Yarn repository in the base image by removing it
RUN rm -f /etc/apt/sources.list.d/yarn.list

# Set bash as the default shell for RUN commands
SHELL ["/bin/bash", "-c"]

# Install additional tools not in python base image
RUN apt-get update && apt-get install -y --no-install-recommends \
    sshpass \
    rsync \
    make

# Clean up apt lists to reduce image size
RUN rm -rf /var/lib/apt/lists/*

# Install uv for Python package management
RUN pip install --timeout 100 --retries 5 uv
# COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv

# Setup directories with proper permissions for vscode user
RUN mkdir -p \
    /home/vscode/.cache/uv \
    /home/vscode/.venv \
    /home/vscode/.cline \
    /home/vscode/.npm \
    /home/vscode/.config/gcloud \
    /home/vscode/.bash_history_dir \
    /home/vscode/.vscode-server \
    /home/vscode/.vscode-server/extensions \
    /home/vscode/.vscode-server/bin \
    /home/vscode/.vscode-server/data \
    && chown -R vscode:vscode /home/vscode \
    && chmod -R 755 /home/vscode

USER vscode
WORKDIR /workspace

# Environment variables
ENV UV_PROJECT_ENVIRONMENT=/home/vscode/.venv
ENV PATH="/home/vscode/.venv/bin:$PATH"


