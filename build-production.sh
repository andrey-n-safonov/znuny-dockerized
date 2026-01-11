#!/bin/bash
# Script to build Production Znuny Docker image with minimal layers
# Uses Dockerfile.production with all RUN commands combined for smallest size

set -e

# Configuration
IMAGE_NAME="andreynsafonov/znuny"
VERSION="7.2.3"

echo "======================================"
echo "Building PRODUCTION Znuny Docker image"
echo "======================================"
echo ""
echo "Image: ${IMAGE_NAME}"
echo "Version: ${VERSION}"
echo ""
echo "Using Dockerfile.production with minimal layers"
echo ""

# Build using production Dockerfile
docker build -f Dockerfile.production -t ${IMAGE_NAME}:${VERSION} .

# Tag as latest
docker tag ${IMAGE_NAME}:${VERSION} ${IMAGE_NAME}:latest

echo ""
echo "=========================================="
echo "✓ Production build complete!"
echo "=========================================="
echo ""
echo "Images created:"
echo "  - ${IMAGE_NAME}:${VERSION} (production)"
echo "  - ${IMAGE_NAME}:latest (production)"
echo ""
echo "Image size:"
docker images ${IMAGE_NAME}:${VERSION}
echo ""
echo "Image comparison:"
docker images | grep "${IMAGE_NAME}" | head -5
echo ""
echo "To test production image with PostgreSQL:"
echo "  IMAGE_TAG=latest docker compose up -d"
echo ""
echo "To test production image with MySQL:"
echo "  IMAGE_TAG=latest docker compose --profile mysql up -d znuny-mysql mysql"
echo ""
echo "To push production images to Docker Hub:"
echo "  docker push ${IMAGE_NAME}:${VERSION}"
echo "  docker push ${IMAGE_NAME}:latest"