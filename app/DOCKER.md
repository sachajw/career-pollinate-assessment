# Docker Build Guide

This guide explains how to build and run the Applicant Validator Docker image.

**Domain Service**: Loan applicant fraud risk validation for FinSure Capital.

## Quick Start

### Build for Current Platform

```bash
docker build -t applicant-validator:latest .
```

### Run Locally

```bash
docker run -d \
  --name applicant-validator \
  -p 8080:8080 \
  -e RISKSHIELD_API_KEY=your-api-key \
  applicant-validator:latest
```

### Test the API

```bash
# Health check
curl http://localhost:8080/health

# API documentation
open http://localhost:8080/docs
```

## Build Targets

The Dockerfile has three stages. Use `--target` to select which one to build:

### Production (Default)

```bash
# Build production image (optimized, ~216MB)
docker build -t applicant-validator:latest .

# Or explicitly specify target
docker build --target production -t applicant-validator:prod .
```

### Development

The development stage includes testing tools and enables hot reload:

```bash
# Build development image
docker build --target development -t applicant-validator:dev .

# Run with hot reload (mount source code)
docker run -p 8080:8080 \
  -e RISKSHIELD_API_KEY=test-key \
  -v ./src:/app/src \
  applicant-validator:dev
```

### Run Tests in Container

```bash
# Build development image
docker build --target development -t applicant-validator:test .

# Run pytest
docker run --rm \
  -e RISKSHIELD_API_KEY=test-key \
  applicant-validator:test \
  pytest -v --cov=src

# Run specific test file
docker run --rm \
  -e RISKSHIELD_API_KEY=test-key \
  -v ./tests:/app/tests \
  applicant-validator:test \
  pytest tests/unit/test_models.py -v
```

### Target Comparison

| Target | Size | Hot Reload | Test Tools | Use Case |
|--------|------|------------|------------|----------|
| `production` | ~216MB | ❌ | ❌ | Deployments |
| `development` | ~250MB | ✅ | ✅ | Local dev, testing |

## Multi-Architecture Builds

### Prerequisites

1. **Docker Buildx** (included in Docker Desktop)
2. **QEMU** for cross-platform emulation (optional, for local testing)

```bash
# Verify buildx is available
docker buildx version

# Create a new builder instance
docker buildx create --name multiarch-builder --use
```

### Build for Multiple Platforms

#### Option 1: Build and Push to Registry

Build for both **amd64** (x86_64) and **arm64** platforms and push to a container registry:

```bash
# Using Docker Hub
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -t your-username/applicant-validator:1.0.0 \
  -t your-username/applicant-validator:latest \
  --push \
  .

# Using GitHub Container Registry
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -t ghcr.io/your-org/applicant-validator:1.0.0 \
  -t ghcr.io/your-org/applicant-validator:latest \
  --push \
  .

# Using Azure Container Registry (FinRisk platform)
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -t acrfinriskdev.azurecr.io/applicant-validator:1.0.0 \
  -t acrfinriskdev.azurecr.io/applicant-validator:latest \
  --push \
  .
```

#### Option 2: Build for Local Testing

**Note**: `--load` only supports a single platform at a time.

```bash
# Build for arm64 (Apple Silicon, ARM servers)
docker buildx build \
  --platform linux/arm64 \
  -t applicant-validator:latest-arm64 \
  --load \
  .

# Build for amd64 (x86_64, most cloud VMs)
docker buildx build \
  --platform linux/amd64 \
  -t applicant-validator:latest-amd64 \
  --load \
  .
```

### Using the Build Script

The `build-multiarch.sh` script simplifies multi-arch builds:

```bash
# Make executable (if needed)
chmod +x build-multiarch.sh

# Build for current platform only (default)
./build-multiarch.sh

# Build and push multi-arch to registry
PUSH=true REGISTRY=ghcr.io/your-org ./build-multiarch.sh

# Custom version
VERSION=2.0.0 ./build-multiarch.sh

# Custom platforms
PLATFORMS=linux/amd64,linux/arm64,linux/arm/v7 ./build-multiarch.sh
```

## Image Details

### Image Stages

1. **Builder Stage** (`builder`)
   - Base: `python:3.13-slim`
   - Installs build dependencies
   - Installs `uv` package manager
   - Creates virtual environment
   - Installs Python dependencies

2. **Production Stage** (`production`)
   - Base: `python:3.13-slim`
   - Copies virtual environment from builder
   - Runs as non-root user (`appuser`)
   - Includes health check
   - **Image Size**: ~370MB

3. **Development Stage** (`development`)
   - Extends production
   - Adds development/testing dependencies
   - Enables hot reload

### Image Size Optimization

The multi-stage build reduces image size by:

- Not including build tools in final image
- Using slim Python base image
- Cleaning up apt cache
- Using `uv` for fast, efficient dependency installation

### Security Features

- ✅ Runs as non-root user (UID 1000)
- ✅ No secrets in image layers
- ✅ Minimal attack surface (slim base image)
- ✅ Health checks enabled
- ✅ Python bytecode optimization disabled (for debugging)

## Environment Variables

| Variable             | Default | Description                       |
| -------------------- | ------- | --------------------------------- |
| `PORT`               | `8080`  | Application port                  |
| `ENVIRONMENT`        | `dev`   | Environment (dev/staging/prod)    |
| `LOG_LEVEL`          | `INFO`  | Logging level                     |
| `RISKSHIELD_API_KEY` | -       | RiskShield API key (required)     |
| `RISKSHIELD_API_URL` | -       | RiskShield API endpoint           |
| `KEY_VAULT_URL`      | -       | Azure Key Vault URL (optional)    |
| `CORS_ORIGINS`       | `[]`    | Allowed CORS origins (JSON array) |

## Docker Compose

For local development with dependencies:

```yaml
version: "3.8"

services:
  api:
    build:
      context: .
      target: development
    ports:
      - "8080:8080"
    environment:
      - ENVIRONMENT=dev
      - LOG_LEVEL=DEBUG
      - RISKSHIELD_API_KEY=test-key
      - RISKSHIELD_API_URL=https://api.riskshield.example.com/v1
    volumes:
      - ./src:/app/src # Hot reload
    command: uvicorn src.main:app --host 0.0.0.0 --port 8080 --reload
```

Save as `docker-compose.yml` and run:

```bash
docker compose up
```

## CI/CD Integration

### GitHub Actions

```yaml
name: Build and Push Docker Image

on:
  push:
    branches: [main]
    tags: ["v*"]

jobs:
  docker:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Login to GitHub Container Registry
        uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Build and push
        uses: docker/build-push-action@v5
        with:
          context: ./app
          platforms: linux/amd64,linux/arm64
          push: true
          tags: |
            ghcr.io/${{ github.repository }}/applicant-validator:latest
            ghcr.io/${{ github.repository }}/applicant-validator:${{ github.sha }}
          cache-from: type=gha
          cache-to: type=gha,mode=max
```

### Azure DevOps (FinRisk Platform)

```yaml
- task: Docker@2
  displayName: Build and push multi-arch image
  inputs:
    command: buildAndPush
    repository: acrfinriskdev.azurecr.io/applicant-validator
    containerRegistry: your-acr-service-connection
    tags: |
      $(Build.BuildId)
      latest
    arguments: --platform linux/amd64,linux/arm64
```

## Troubleshooting

### Build fails with "uv: not found"

Make sure the Dockerfile has the correct PATH:

```dockerfile
ENV PATH="/root/.local/bin:$PATH"
```

### Multi-arch build fails with "--load"

`--load` only supports single platform. Use `--push` or build one platform at a time.

### Health check failing

Check logs:

```bash
docker logs applicant-validator
```

Verify the container can reach localhost:8080:

```bash
docker exec applicant-validator curl http://localhost:8080/health
```

## Performance Tips

1. **Build Cache**: Use BuildKit cache mounts for faster builds
2. **Layer Ordering**: Keep frequently changing code at the bottom
3. **Multi-stage**: Leverage multi-stage builds to minimize final image size
4. **Registry**: Use a registry close to your deployment region

## Security Scanning

Scan images for vulnerabilities:

```bash
# Using Docker Scout
docker scout cves applicant-validator:latest

# Using Trivy
trivy image applicant-validator:latest

# Using Snyk
snyk container test applicant-validator:latest
```

## References

- [Docker Multi-platform builds](https://docs.docker.com/build/building/multi-platform/)
- [Docker Buildx](https://docs.docker.com/buildx/working-with-buildx/)
- [Best practices for writing Dockerfiles](https://docs.docker.com/develop/develop-images/dockerfile_best-practices/)
