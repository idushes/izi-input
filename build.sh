#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# Define colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Starting Izi Input Build Process ===${NC}"

# 1. Clone and compile whisper.cpp if needed
if [ ! -d "whisper.cpp" ]; then
    echo -e "${BLUE}[1/6] Cloning whisper.cpp repository...${NC}"
    git clone --depth 1 https://github.com/ggerganov/whisper.cpp.git
else
    echo -e "${GREEN}[1/6] whisper.cpp already cloned.${NC}"
fi

if [ ! -f "whisper.cpp/main" ]; then
    echo -e "${BLUE}[2/6] Compiling whisper.cpp (with Metal GPU acceleration)...${NC}"
    cd whisper.cpp
    make
    cd ..
    echo -e "${GREEN}whisper.cpp compiled successfully.${NC}"
else
    echo -e "${GREEN}[2/6] whisper.cpp already compiled.${NC}"
fi

# 2. Compile Swift sources
echo -e "${BLUE}[3/6] Compiling Swift app...${NC}"
SDK_PATH=$(xcrun --show-sdk-path)

swiftc -O -sdk "$SDK_PATH" \
    -target arm64-apple-macosx13.0 \
    -o IziInput \
    src/*.swift

echo -e "${GREEN}Swift sources compiled successfully.${NC}"

# 3. Create .app bundle structure
echo -e "${BLUE}[4/6] Creating IziInput.app bundle...${NC}"
rm -rf IziInput.app
mkdir -p IziInput.app/Contents/MacOS
mkdir -p IziInput.app/Contents/Resources

# Move compiled Swift binary
mv IziInput IziInput.app/Contents/MacOS/IziInput

# Copy Info.plist
cp Info.plist IziInput.app/Contents/Info.plist

# Copy whisper.cpp binary as whisper-cli resource
cp whisper.cpp/build/bin/whisper-cli IziInput.app/Contents/Resources/whisper-cli

echo -e "${GREEN}App bundle created successfully.${NC}"

# 4. Codesign application
echo -e "${BLUE}[5/6] Codesigning application...${NC}"
codesign -f -s - IziInput.app/Contents/Resources/whisper-cli
codesign -f -s - IziInput.app
echo -e "${GREEN}Codesigning completed successfully.${NC}"

# 5. Clean up temporary build artifacts
echo -e "${BLUE}[6/6] Cleaning up...${NC}"
echo -e "${GREEN}=== Build completed successfully! ===${NC}"
echo -e "${PURPLE}To run the app, type: open IziInput.app${NC}"
