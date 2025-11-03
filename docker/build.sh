#!/bin/bash
# Build script for PBS Client Docker image

set -e

VERSION=${1:-latest}
IMAGE_NAME="pbsclient"

echo "=================================="
echo "Building PBS Client Docker Image"
echo "=================================="
echo "Version: $VERSION"
echo "Image: $IMAGE_NAME:$VERSION"
echo

# Check if scripts directory exists
if [ ! -d "scripts" ]; then
    echo "ERROR: scripts/ directory not found"
    echo "Make sure you're in the correct directory"
    exit 1
fi

# Build the image
echo "Building image..."
docker build -t "$IMAGE_NAME:$VERSION" .

if [ $? -eq 0 ]; then
    echo
    echo "=================================="
    echo "Build successful!"
    echo "=================================="
    echo
    echo "Image: $IMAGE_NAME:$VERSION"
    echo
    echo "Quick test:"
    echo "  docker run --rm $IMAGE_NAME:$VERSION test"
    echo
    echo "Deploy with:"
    echo "  docker-compose -f docker-compose-linux.yml up -d"
    echo "  docker-compose -f docker-compose-windows.yml up -d"
    echo "  docker-compose -f docker-compose-macos.yml up -d"
    echo
else
    echo
    echo "=================================="
    echo "Build failed!"
    echo "=================================="
    exit 1
fi

# Optionally tag as latest
if [ "$VERSION" != "latest" ]; then
    echo "Tagging as latest..."
    docker tag "$IMAGE_NAME:$VERSION" "$IMAGE_NAME:latest"
fi

# Show image size
echo "Image size:"
docker images "$IMAGE_NAME:$VERSION" --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}"
