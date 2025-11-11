#!/usr/bin/env pwsh
# Run script for ComfyUI Docker container on local machine (5090)

param(
    [string]$Version = "0.04",
    [string]$Registry = "local",
    [string]$ContainerName = "comfyui-dgx-local",
    [int]$Port = 8188,
    [string]$ModelsPath = "",
    [string]$InputPath = "",
    [string]$OutputPath = "",
    [string]$TempPath = "",
    [switch]$Detach,
    [string[]]$ExtraArgs = @()
)

$ErrorActionPreference = "Stop"

Write-Host "=========================================="
Write-Host "Running ComfyUI Docker Container"
Write-Host "Version: $Version"
Write-Host "Container Name: $ContainerName"
Write-Host "Port: $Port"
Write-Host "=========================================="

# Set image name
$ImageName = "${Registry}/comfyui-dgx:${Version}-amd64"

# Check if container already exists
$ExistingContainer = docker ps -a --filter "name=$ContainerName" --format "{{.Names}}" 2>$null
if ($ExistingContainer -eq $ContainerName) {
    Write-Host "Stopping and removing existing container: $ContainerName"
    docker stop $ContainerName 2>$null | Out-Null
    docker rm $ContainerName 2>$null | Out-Null
}

# Build docker run arguments
$DockerArgs = @(
    "run"
)

# Add detach flag
if ($Detach) {
    $DockerArgs += "-d"
} else {
    $DockerArgs += "-it"
}

# Add container name
$DockerArgs += "--name", $ContainerName

# Add GPU support
$DockerArgs += "--gpus", "all"

# Add port mapping
$DockerArgs += "-p", "${Port}:8188"

# Add volume mounts for custom paths
if ($ModelsPath) {
    Write-Host "Mounting models path: $ModelsPath"
    $DockerArgs += "-v", "${ModelsPath}:/workspace/ComfyUI/models"
    $DockerArgs += "-e", "MODEL_BASE_PATH=/workspace/ComfyUI/models"
}

if ($InputPath) {
    Write-Host "Mounting input path: $InputPath"
    $DockerArgs += "-v", "${InputPath}:/workspace/ComfyUI/input"
    $DockerArgs += "-e", "INPUT_DIR=/workspace/ComfyUI/input"
}

if ($OutputPath) {
    Write-Host "Mounting output path: $OutputPath"
    $DockerArgs += "-v", "${OutputPath}:/workspace/ComfyUI/output"
    $DockerArgs += "-e", "OUTPUT_DIR=/workspace/ComfyUI/output"
}

if ($TempPath) {
    Write-Host "Mounting temp path: $TempPath"
    $DockerArgs += "-v", "${TempPath}:/workspace/ComfyUI/temp"
    $DockerArgs += "-e", "TEMP_DIR=/workspace/ComfyUI/temp"
}

# Add environment variables
$DockerArgs += "-e", "COMFYUI_PORT=8188"

# Add restart policy
$DockerArgs += "--restart", "unless-stopped"

# Add image name
$DockerArgs += $ImageName

# Add extra arguments to ComfyUI
if ($ExtraArgs.Count -gt 0) {
    $DockerArgs += $ExtraArgs
}

Write-Host ""
Write-Host "Executing: docker $($DockerArgs -join ' ')"
Write-Host ""

# Run the container
& docker @DockerArgs

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "=========================================="
    Write-Host "Container started successfully!"
    Write-Host "=========================================="
    Write-Host "ComfyUI is available at: http://localhost:$Port"
    Write-Host ""
    Write-Host "To view logs:"
    Write-Host "  docker logs -f $ContainerName"
    Write-Host ""
    Write-Host "To stop the container:"
    Write-Host "  docker stop $ContainerName"
    Write-Host ""
    Write-Host "To remove the container:"
    Write-Host "  docker rm $ContainerName"
} else {
    Write-Host ""
    Write-Host "=========================================="
    Write-Host "Failed to start container!"
    Write-Host "Exit code: $LASTEXITCODE"
    Write-Host "=========================================="
    exit $LASTEXITCODE
}