#!/bin/bash
set -e

REPO="mslxi/Liquid-Glass-Prism-dns"
PROJECT_DIR="/Users/cike567/Documents/worker doc/dns/prism-selfhost"
OUTPUT_DIR="/tmp/prism-binaries"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

get_next_version() {
    local latest=$(gh release list --repo "$REPO" --limit 1 2>/dev/null | grep -v "beta" | head -1 | awk '{print $1}')
    
    if [ -z "$latest" ]; then
        echo "1.0"
        return
    fi
    
    local major=$(echo "$latest" | sed 's/v//' | cut -d. -f1)
    local minor=$(echo "$latest" | sed 's/v//' | cut -d. -f2 | cut -d- -f1)
    
    local new_minor=$((minor + 1))
    echo "${major}.${new_minor}"
}

IS_BETA=false
RELEASE_OPTS=""

if [[ "$1" == "--beta" ]]; then
    IS_BETA=true
    VERSION="v1.0.$(date +%Y%m%d%H%M)-beta"
    RELEASE_OPTS="--prerelease"
    echo -e "${YELLOW}[MODE] Beta release${NC}"
else
    VERSION="v$(get_next_version)"
    echo -e "${GREEN}[MODE] Stable release: ${VERSION}${NC}"
fi

cd "$PROJECT_DIR"

LDFLAGS="-s -w -X 'prism/pkg/version.Version=${VERSION}' -X 'prism/pkg/version.BuildTime=$(date -u '+%Y-%m-%d %H:%M:%S')' -X 'prism/pkg/version.GitCommit=$(git rev-parse --short HEAD 2>/dev/null || echo unknown)'"

mkdir -p "$OUTPUT_DIR"

echo -e "${BLUE}[BUILD]${NC} Building frontend..."
cd web
npm install --silent 2>/dev/null || npm install
npm run build -- --outDir ../cmd/controller/dist
cd ..

echo -e "${BLUE}[BUILD]${NC} prism-controller linux/amd64..."
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -ldflags="$LDFLAGS" -o "${OUTPUT_DIR}/prism-controller-linux-amd64" cmd/controller/main.go

echo -e "${BLUE}[BUILD]${NC} prism-controller linux/arm64..."
CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -ldflags="$LDFLAGS" -o "${OUTPUT_DIR}/prism-controller-linux-arm64" cmd/controller/main.go

echo -e "${BLUE}[BUILD]${NC} prism-controller darwin/amd64..."
CGO_ENABLED=0 GOOS=darwin GOARCH=amd64 go build -ldflags="$LDFLAGS" -o "${OUTPUT_DIR}/prism-controller-darwin-amd64" cmd/controller/main.go

echo -e "${BLUE}[BUILD]${NC} prism-controller darwin/arm64..."
CGO_ENABLED=0 GOOS=darwin GOARCH=arm64 go build -ldflags="$LDFLAGS" -o "${OUTPUT_DIR}/prism-controller-darwin-arm64" cmd/controller/main.go

echo -e "${BLUE}[BUILD]${NC} prism-agent linux/amd64..."
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -ldflags="$LDFLAGS" -o "${OUTPUT_DIR}/prism-agent_linux_amd64" cmd/agent/main.go

echo -e "${BLUE}[BUILD]${NC} prism-agent linux/arm64..."
CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -ldflags="$LDFLAGS" -o "${OUTPUT_DIR}/prism-agent_linux_arm64" cmd/agent/main.go

echo ""
echo -e "${GREEN}[OK]${NC} All binaries built:"
ls -lh "$OUTPUT_DIR"

echo ""
echo -e "${BLUE}[RELEASE]${NC} Creating GitHub release ${VERSION}..."

gh release create "$VERSION" \
    "${OUTPUT_DIR}/prism-controller-linux-amd64" \
    "${OUTPUT_DIR}/prism-controller-linux-arm64" \
    "${OUTPUT_DIR}/prism-controller-darwin-amd64" \
    "${OUTPUT_DIR}/prism-controller-darwin-arm64" \
    "${OUTPUT_DIR}/prism-agent_linux_amd64" \
    "${OUTPUT_DIR}/prism-agent_linux_arm64" \
    --repo "$REPO" \
    --title "Release $VERSION" \
    --generate-notes \
    $RELEASE_OPTS

echo ""
echo -e "${GREEN}[OK]${NC} Release created: https://github.com/$REPO/releases/tag/$VERSION"

rm -rf "$OUTPUT_DIR"
echo -e "${GREEN}[OK]${NC} Cleaned up temp files"
