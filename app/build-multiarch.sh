#!/bin/bash
# Build multi-architecture Docker images for Risk Scoring API
# Supports: linux/amd64, linux/arm64

set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
IMAGE_NAME="${IMAGE_NAME:-risk-scoring-api}"
VERSION="${VERSION:-1.0.0}"
REGISTRY="${REGISTRY:-}"  # e.g., ghcr.io/your-org or docker.io/username
PLATFORMS="${PLATFORMS:-linux/amd64,linux/arm64}"
PUSH="${PUSH:-false}"

echo -e "${BLUE}===========================================
Docker Multi-Architecture Build
===========================================${NC}"

echo -e "${GREEN}Configuration:${NC}"
echo "  Image Name: ${IMAGE_NAME}"
echo "  Version: ${VERSION}"
echo "  Platforms: ${PLATFORMS}"
echo "  Registry: ${REGISTRY:-<none>}"
echo "  Push: ${PUSH}"
echo ""

# Build tags
TAGS=""
if [ -n "$REGISTRY" ]; then
    TAGS="-t ${REGISTRY}/${IMAGE_NAME}:${VERSION} -t ${REGISTRY}/${IMAGE_NAME}:latest"
else
    TAGS="-t ${IMAGE_NAME}:${VERSION} -t ${IMAGE_NAME}:latest"
fi

# Check if buildx builder exists, create if not
BUILDER_NAME="multiarch-builder"
if ! docker buildx inspect ${BUILDER_NAME} > /dev/null 2>&1; then
    echo -e "${YELLOW}Creating buildx builder: ${BUILDER_NAME}${NC}"
    docker buildx create --name ${BUILDER_NAME} --use
else
    echo -e "${GREEN}Using existing buildx builder: ${BUILDER_NAME}${NC}"
    docker buildx use ${BUILDER_NAME}
fi

# Build command
BUILD_CMD="docker buildx build --platform ${PLATFORMS}"

if [ "$PUSH" = "true" ]; then
    if [ -z "$REGISTRY" ]; then
        echo -e "${YELLOW}Warning: PUSH=true but no REGISTRY specified${NC}"
        echo "Please set REGISTRY environment variable to push images"
        exit 1
    fi
    BUILD_CMD="${BUILD_CMD} --push"
    echo -e "${YELLOW}Building and pushing to registry...${NC}"
else
    # For local testing, use --output to save to docker
    BUILD_CMD="${BUILD_CMD} --load"
    echo -e "${YELLOW}Note: --load only supports single platform. Building for current platform only.${NC}"
    # Detect current platform
    ARCH=$(uname -m)
    if [ "$ARCH" = "arm64" ] || [ "$ARCH" = "aarch64" ]; then
        PLATFORMS="linux/arm64"
    else
        PLATFORMS="linux/amd64"
    fi
    BUILD_CMD="docker buildx build --platform ${PLATFORMS}"
    BUILD_CMD="${BUILD_CMD} --load"
fi

BUILD_CMD="${BUILD_CMD} ${TAGS} ."

echo -e "${BLUE}Running: ${BUILD_CMD}${NC}"
echo ""

# Execute build
eval ${BUILD_CMD}

echo ""
echo -e "${GREEN}===========================================
Build Complete!
===========================================${NC}"

if [ "$PUSH" = "true" ]; then
    echo -e "${GREEN}Images pushed to:${NC}"
    if [ -n "$REGISTRY" ]; then
        echo "  ${REGISTRY}/${IMAGE_NAME}:${VERSION}"
        echo "  ${REGISTRY}/${IMAGE_NAME}:latest"
    fi
else
    echo -e "${GREEN}Image built locally:${NC}"
    echo "  ${IMAGE_NAME}:${VERSION}"
    echo "  ${IMAGE_NAME}:latest"
    echo ""
    echo -e "${YELLOW}To build and push multi-arch images:${NC}"
    echo "  PUSH=true REGISTRY=your-registry.io/your-org ./build-multiarch.sh"
fi

echo ""
echo -e "${BLUE}Available platforms:${NC}"
docker buildx imagetools inspect ${IMAGE_NAME}:${VERSION} 2>/dev/null || echo "  (Image not in registry yet)"
