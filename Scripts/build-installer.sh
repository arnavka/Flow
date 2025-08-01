#!/bin/bash

# build-installer.sh - Build and create a signed DMG installer for Petrichor

set -e  # Exit on error

# Configuration
APP_NAME="Petrichor"
SCHEME="Petrichor"
CONFIGURATION="Release"
PROJECT="Petrichor.xcodeproj"
NOTARY_PROFILE="Petrichor"

# Read from environment variables
TEAM_ID="${PETRICHOR_TEAM_ID:-}"
DEVELOPER_ID="${PETRICHOR_DEVELOPER_ID:-}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions
log() { echo -e "✅ $1"; }
error() { echo -e "❌ $1" >&2; }
warning() { echo -e "⚠️  $1"; }
info() { echo -e "ℹ️  $1"; }

# Check required tools
check_requirements() {
    local missing_tools=()
    
    # Check for Xcode
    if ! command -v xcodebuild >/dev/null 2>&1; then
        missing_tools+=("xcodebuild (Install Xcode from App Store)")
    fi
    
    # Check for git
    if ! command -v git >/dev/null 2>&1; then
        missing_tools+=("git (Install Xcode Command Line Tools)")
    fi
    
    # Check for codesign
    if ! command -v codesign >/dev/null 2>&1; then
        missing_tools+=("codesign (Install Xcode Command Line Tools)")
    fi
    
    # Check for notarytool (if not bypassing)
    if [ "$BYPASS_NOTARY" = false ] && ! command -v xcrun >/dev/null 2>&1; then
        missing_tools+=("xcrun (Install Xcode Command Line Tools)")
    fi
    
    # Check optional tools
    if ! command -v xcpretty >/dev/null 2>&1; then
        warning "xcpretty not found - install with: gem install xcpretty"
        warning "Build output will be verbose without xcpretty"
    fi
    
    if ! command -v create-dmg >/dev/null 2>&1; then
        warning "create-dmg not found - install with: brew install create-dmg"
        warning "Using fallback DMG creation method"
    fi
    
    # Exit if required tools are missing
    if [ ${#missing_tools[@]} -gt 0 ]; then
        error "Missing required tools:"
        for tool in "${missing_tools[@]}"; do
            error "  - $tool"
        done
        echo ""
        error "Please install the missing tools and try again."
        exit 1
    fi
    
    # Auto-detect project directory
    if [ -e "$PROJECT" ]; then
        # Already in project root (-e checks if exists, whether file or directory)
        PROJECT_ROOT="."
    elif [ -e "../$PROJECT" ]; then
        # In Scripts directory
        PROJECT_ROOT=".."
        cd "$PROJECT_ROOT"
        log "Changed to project root directory"
    else
        error "Cannot find $PROJECT"
        error "Please run this script from the project root or Scripts directory"
        exit 1
    fi
}

# Progress animation
show_progress() {
    local pid=$1
    tput civis  # Hide cursor
    while kill -0 $pid 2>/dev/null; do
        for dots in "" "." ".." "..."; do
            printf "\r   Building%-4s " "$dots"
            sleep 0.1
            kill -0 $pid 2>/dev/null || break
        done
    done
    printf "\r                    \r"
    tput cnorm  # Show cursor
}

# Run xcodebuild with standard parameters
run_build() {
    local action="$1"
    local log_file="$2"
    local arch="$3"
    shift 3
    
    # Configure signing based on bypass flag
    local sign_config=""
    if [ "$BYPASS_NOTARY" = true ]; then
        sign_config="CODE_SIGN_IDENTITY='' CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO DEVELOPMENT_TEAM=''"
    else
        sign_config="DEVELOPMENT_TEAM='$TEAM_ID' CODE_SIGN_IDENTITY='$DEVELOPER_ID' CODE_SIGNING_REQUIRED=YES CODE_SIGNING_ALLOWED=YES CODE_SIGN_STYLE=Manual ENABLE_HARDENED_RUNTIME=YES OTHER_CODE_SIGN_FLAGS='--timestamp --options=runtime'"
    fi
    
    local cmd="xcodebuild $action \
        -project '$PROJECT' \
        -scheme '$SCHEME' \
        -configuration '$CONFIGURATION' \
        $sign_config \
        MARKETING_VERSION='$VERSION' \
        CURRENT_PROJECT_VERSION='$VERSION' \
        ARCHS='$arch' \
        ONLY_ACTIVE_ARCH=NO \
        $*"
    
    if [ "$VERBOSE" = false ]; then
        cmd="$cmd -quiet"
        if command -v xcpretty >/dev/null 2>&1; then
            (eval "$cmd" 2>&1 | tee "$log_file" | xcpretty --no-utf --simple >/dev/null 2>&1) &
            local pid=$!
            show_progress $pid
            wait $pid
            return $?
        fi
    fi
    
    eval "$cmd" 2>&1 | tee "$log_file"
    return ${PIPESTATUS[0]}
}

# Notarize function (app or dmg)
notarize() {
    local file="$1"
    local type="$2"
    
    info "Notarizing $type (this may take 5-15 minutes)..."
    
    # Create zip if it's an app
    if [[ "$file" == *.app ]]; then
        local zip_path="${file}.zip"
        ditto -c -k --keepParent "$file" "$zip_path"
        file="$zip_path"
    fi
    
    # Submit for notarization
    if xcrun notarytool submit "$file" --keychain-profile "$NOTARY_PROFILE" --wait; then
        log "$type notarization completed"
        
        # Staple the ticket (use original path for .app)
        local staple_target="${1}"
        xcrun stapler staple "$staple_target"
        
        # Clean up zip if created
        [[ "$file" == *.zip ]] && rm -f "$file"
        return 0
    else
        error "$type notarization failed!"
        [[ "$file" == *.zip ]] && rm -f "$file"
        return 1
    fi
}

# Create DMG for specific architecture
create_installer() {
    local arch="$1"
    local suffix="$2"
    local display_name="$3"
    
    log "Building $display_name version..."
    
    local archive_path="$BUILD_DIR/$APP_NAME-$suffix.xcarchive"
    local export_path="$BUILD_DIR/export-$suffix"
    local dmg_path="$BUILD_DIR/${APP_NAME}-${VERSION}-$suffix.dmg"
    local error_log="$BUILD_DIR/build-$suffix.log"
    
    # Step 1: Archive
    info "Archiving for $display_name..."
    run_build archive "$error_log" "$arch" \
        -archivePath "$archive_path" \
        -destination "platform=macOS"
    
    if [ ! -d "$archive_path" ]; then
        error "Archive failed for $display_name! Check $error_log for details"
        grep -E "(error:|ERROR:|failed|FAILED)" "$error_log" 2>/dev/null | tail -10
        return 1
    fi
    
    # Step 2: Export
    info "Exporting signed app..."
    mkdir -p "$export_path"
    
    if [ "$BYPASS_NOTARY" = true ]; then
        # For ad-hoc builds, extract and sign manually
        cp -R "$archive_path/Products/Applications/$APP_NAME.app" "$export_path/" || {
            error "Failed to extract app from archive"; return 1
        }
        codesign --force --deep --sign "-" "$export_path/$APP_NAME.app" || {
            error "Failed to ad-hoc sign app"; return 1
        }
    else
        # Export with Developer ID
        cat > "$BUILD_DIR/exportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>$TEAM_ID</string>
</dict>
</plist>
EOF
        xcodebuild -exportArchive \
            -archivePath "$archive_path" \
            -exportPath "$export_path" \
            -exportOptionsPlist "$BUILD_DIR/exportOptions.plist" &>/dev/null
        
        [ -d "$export_path/$APP_NAME.app" ] || { error "Export failed"; return 1; }
    fi
    
    # Step 3: Notarize app (skip if bypassing)
    if [ "$BYPASS_NOTARY" = false ]; then
        notarize "$export_path/$APP_NAME.app" "app" || return 1
    else
        warning "Skipping app notarization (ad-hoc signed)"
    fi
    
    # Step 4: Create DMG
    info "Creating DMG for $display_name..."
    cd "$export_path"
    
    if command -v create-dmg >/dev/null 2>&1; then
        local dmg_title="$APP_NAME $VERSION"
        [ "$suffix" != "Universal" ] && dmg_title="$APP_NAME-$suffix"
        create-dmg "$APP_NAME.app" --dmg-title="$dmg_title" || {
            error "create-dmg failed"; return 1
        }
        mv *.dmg "../${APP_NAME}-${VERSION}-$suffix.dmg"
    else
        # Fallback to hdiutil
        cd ..
        DMG_DIR="$BUILD_DIR/dmg-$suffix"
        mkdir -p "$DMG_DIR"
        cp -R "$export_path/$APP_NAME.app" "$DMG_DIR/"
        ln -s /Applications "$DMG_DIR/Applications"
        hdiutil create -volname "$APP_NAME $VERSION" \
            -srcfolder "$DMG_DIR" -ov -format UDZO "$dmg_path"
        rm -rf "$DMG_DIR"
    fi
    
    cd - >/dev/null
    [ -f "$dmg_path" ] || { error "DMG creation failed!"; return 1; }
    
    # Step 5: Sign and notarize DMG
    local sign_id="$DEVELOPER_ID"
    [ "$BYPASS_NOTARY" = true ] && sign_id="-"
    
    info "Signing DMG..."
    codesign --force --sign "$sign_id" "$dmg_path"
    
    if [ "$BYPASS_NOTARY" = false ]; then
        notarize "$dmg_path" "DMG" || return 1
    else
        warning "Skipping DMG notarization (ad-hoc signed)"
    fi
    
    # Generate checksum
    cd "$BUILD_DIR" && shasum -a 256 "$(basename "$dmg_path")" > "$(basename "$dmg_path").sha256" && cd - >/dev/null
    
    # Cleanup
    rm -rf "$archive_path" "$export_path" "$error_log" "$BUILD_DIR/exportOptions.plist"
    
    log "$display_name installer created: $dmg_path"
    return 0
}

# Print usage
print_usage() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  --version <version>  Specify version number (e.g., 1.0.0)"
    echo "  --verbose           Show full build output"
    echo "  --universal         Build universal binary (default)"
    echo "  --intel-only        Build Intel-only installer"
    echo "  --arm-only          Build Apple Silicon-only installer"
    echo "  --separate          Build separate Intel and Apple Silicon installers"
    echo "  --bypass-notary     Skip notarization and use ad-hoc signing"
    echo "  --help              Show this help message"
}

# Print bypass instructions
print_bypass_instructions() {
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}⚠️  Ad-hoc Signed Build - Manual Installation Required${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    
    echo -e "This build is not notarized and will be blocked by Gatekeeper."
    echo -e "Users must manually bypass Gatekeeper to install:\n"
    
    echo -e "${GREEN}Option 1: Remove quarantine from DMG and App${NC}"
    echo -e "  ${YELLOW}# For the DMG:${NC}"
    echo -e "  xattr -cr ~/Downloads/Petrichor-*.dmg\n"
    echo -e "  ${YELLOW}# After installing, for the app:${NC}"
    echo -e "  xattr -cr /Applications/Petrichor.app\n"
    
    echo -e "${GREEN}Option 2: Right-click method${NC}"
    echo -e "  1. Right-click the DMG → Open"
    echo -e "  2. Right-click Petrichor.app → Open"
    echo -e "  3. Click 'Open' in the warning dialog\n"
    
    echo -e "${GREEN}Option 3: System Settings${NC}"
    echo -e "  1. Try to open the app (it will be blocked)"
    echo -e "  2. Go to System Settings → Privacy & Security"
    echo -e "  3. Click 'Open Anyway' next to the Petrichor blocked message\n"
    
    echo -e "${YELLOW}Note:${NC} This build is for testing only, not for distribution to end users.\n"
}

# Parse arguments
VERSION=""
VERBOSE=false
BUILD_UNIVERSAL=true
BUILD_INTEL=false
BUILD_ARM=false
BYPASS_NOTARY=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --version) VERSION="$2"; shift 2 ;;
        --verbose) VERBOSE=true; shift ;;
        --universal) BUILD_UNIVERSAL=true; BUILD_INTEL=false; BUILD_ARM=false; shift ;;
        --intel-only) BUILD_INTEL=true; BUILD_UNIVERSAL=false; BUILD_ARM=false; shift ;;
        --arm-only) BUILD_ARM=true; BUILD_UNIVERSAL=false; BUILD_INTEL=false; shift ;;
        --separate) BUILD_UNIVERSAL=false; BUILD_INTEL=true; BUILD_ARM=true; shift ;;
        --bypass-notary) BYPASS_NOTARY=true; shift ;;
        --help) print_usage; exit 0 ;;
        *) error "Unknown option: $1"; exit 1 ;;
    esac
done

# Validate environment variables (skip if bypassing notarization)
if [ "$BYPASS_NOTARY" = false ]; then
    if [ -z "$TEAM_ID" ] || [ -z "$DEVELOPER_ID" ]; then
        error "Missing required environment variables for notarization!"
        echo ""
        echo "Please set the following environment variables:"
        echo "  export PETRICHOR_TEAM_ID=\"your-team-id\""
        echo "  export PETRICHOR_DEVELOPER_ID=\"Developer ID Application: Your Name (TEAMID)\""
        echo ""
        echo "Example:"
        echo "  export PETRICHOR_TEAM_ID=\"ABCD1234XY\""
        echo "  export PETRICHOR_DEVELOPER_ID=\"Developer ID Application: John Doe (ABCD1234XY)\""
        echo ""
        echo "Or run with --bypass-notary to skip notarization:"
        echo "  $0 --bypass-notary"
        exit 1
    fi
fi

# Check for notarization credentials (skip if bypassing)
if [ "$BYPASS_NOTARY" = false ]; then
    if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" &>/dev/null; then
        error "Notarization credentials not found!"
        error "Please run: xcrun notarytool store-credentials '$NOTARY_PROFILE'"
        error "  --apple-id 'your-apple-id@email.com'"
        error "  --team-id '$TEAM_ID'"
        error "  --password 'your-app-specific-password'"
        exit 1
    fi
else
    warning "Bypassing notarization - will use ad-hoc signing"
fi

# Check requirements
check_requirements

# Detect version if not specified
if [ -z "$VERSION" ]; then
    # Get the last tag
    LAST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "")
    
    if [ -n "$LAST_TAG" ]; then
        # Check if HEAD is at the tag
        TAG_COMMIT=$(git rev-list -n 1 "$LAST_TAG" 2>/dev/null)
        HEAD_COMMIT=$(git rev-parse HEAD 2>/dev/null)
        
        if [ "$TAG_COMMIT" = "$HEAD_COMMIT" ]; then
            # No commits since tag, use tag version
            VERSION="${LAST_TAG#v}"  # Remove 'v' prefix if present
            log "At tag $LAST_TAG, using version: $VERSION"
        else
            # Commits exist after tag, use dev version
            SHORT_SHA=$(git rev-parse --short=8 HEAD)
            VERSION="dev-${SHORT_SHA}"
            log "Commits found after $LAST_TAG, using development version: $VERSION"
        fi
    else
        # No tags found, use dev version
        SHORT_SHA=$(git rev-parse --short=8 HEAD 2>/dev/null || echo "unknown")
        VERSION="dev-${SHORT_SHA}"
        log "No tags found, using development version: $VERSION"
    fi
fi

# Setup paths
BUILD_DIR="build"

# Prepare build directory
log "Building $APP_NAME version $VERSION"
rm -rf "$BUILD_DIR" && mkdir -p "$BUILD_DIR"

# Build based on selected options
[ "$BUILD_UNIVERSAL" = true ] && create_installer "x86_64 arm64" "Universal" "Universal"
[ "$BUILD_INTEL" = true ] && [ "$BUILD_UNIVERSAL" = false ] && create_installer "x86_64" "Intel" "Intel"
[ "$BUILD_ARM" = true ] && [ "$BUILD_UNIVERSAL" = false ] && create_installer "arm64" "AppleSilicon" "Apple Silicon"

# Summary
echo -e "\n${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✅ Build completed successfully!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

# List all created DMGs
for dmg in "$BUILD_DIR"/*.dmg; do
    if [ -f "$dmg" ]; then
        echo -e "📦 $(basename "$dmg")"
        echo -e "   📏 Size: ${GREEN}$(du -h "$dmg" | cut -f1)${NC}"
        echo -e "   📋 SHA256: ${GREEN}$(cat "$dmg.sha256" | awk '{print $1}')${NC}"
        if [ "$BYPASS_NOTARY" = true ]; then
            echo -e "   ⚠️  ${YELLOW}Ad-hoc signed (not notarized)${NC}"
        else
            echo -e "   ✅ Notarized and ready for distribution"
        fi
        echo ""
    fi
done

# Show bypass instructions if applicable
[ "$BYPASS_NOTARY" = true ] && print_bypass_instructions

# GitHub Actions outputs (for the first DMG found)
if [ -n "$GITHUB_ACTIONS" ]; then
    for dmg in "$BUILD_DIR"/*.dmg; do
        if [ -f "$dmg" ]; then
            {
                echo "dmg-path=$dmg"
                echo "dmg-name=$(basename "$dmg")"
                echo "version=$VERSION"
                echo "sha256=$(cat "$dmg.sha256" | awk '{print $1}')"
            } >> "$GITHUB_OUTPUT"
            break
        fi
    done
fi

log "Done!"