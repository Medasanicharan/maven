```bash
#!/bin/bash

# ============================================================
# Maven Installation Script for RHEL 10
# Purpose:
#   1. Install Java 21 JDK
#   2. Detect and install the latest stable Maven 3.x
#   3. Configure Maven environment variables permanently
#   4. Make mvn available immediately through /usr/local/bin
#   5. Verify Java and Maven installation
# ============================================================

set -o pipefail

# ------------------------------------------------------------
# Configuration
# ------------------------------------------------------------

JAVA_VERSION="21"

MAVEN_BASE_DIR="/opt"
MAVEN_SYMLINK="${MAVEN_BASE_DIR}/maven"

MAVEN_INDEX_URL="https://dlcdn.apache.org/maven/maven-3/"

PROFILE_FILE="/etc/profile.d/maven.sh"
GLOBAL_BIN="/usr/local/bin"

RUN_SYSTEM_UPDATE="${RUN_SYSTEM_UPDATE:-false}"

LOGFILE="/tmp/maven-install-$(date +%F-%H-%M-%S).log"

# ------------------------------------------------------------
# Colors
# ------------------------------------------------------------

R='\033[31m'
G='\033[32m'
Y='\033[33m'
N='\033[0m'

# ------------------------------------------------------------
# Functions
# ------------------------------------------------------------

VALIDATE() {
    if [ "$1" -ne 0 ]; then
        echo -e "$2...${R} FAILURE ${N}"
        echo "Check log file: $LOGFILE"
        exit 1
    else
        echo -e "$2...${G} SUCCESS ${N}"
    fi
}

SKIP() {
    echo -e "$1...${Y} SKIPPING (already done) ${N}"
}

# ------------------------------------------------------------
# Root User Check
# ------------------------------------------------------------

if [ "$(id -u)" -ne 0 ]; then
    echo -e "${R}Please run this script with root access.${N}"
    echo "Example: sudo sh maven.sh"
    exit 1
fi

# ------------------------------------------------------------
# Start
# ------------------------------------------------------------

echo
echo "============================================================"
echo " Java + Latest Maven 3.x Installation"
echo "============================================================"
echo
echo "Java Version : $JAVA_VERSION"
echo "Maven Home   : $MAVEN_SYMLINK"
echo "Log File     : $LOGFILE"
echo

touch "$LOGFILE" || exit 1

# ------------------------------------------------------------
# System Update (Optional)
# ------------------------------------------------------------

if [ "$RUN_SYSTEM_UPDATE" = "true" ]; then
    dnf update -y --allowerasing >> "$LOGFILE" 2>&1
    VALIDATE $? "System packages update"
else
    SKIP "System packages update (RUN_SYSTEM_UPDATE=false)"
fi

# ------------------------------------------------------------
# Required Packages
# ------------------------------------------------------------

MISSING_PKGS=""

for PKG in wget curl tar gzip
do
    if ! rpm -q "$PKG" &>/dev/null; then
        MISSING_PKGS="$MISSING_PKGS $PKG"
    fi
done

if [ -z "$MISSING_PKGS" ]; then
    SKIP "Installing required packages"
else
    dnf install -y $MISSING_PKGS >> "$LOGFILE" 2>&1
    VALIDATE $? "Installing required packages"
fi

# ------------------------------------------------------------
# Install Java 21 JDK
# ------------------------------------------------------------

if rpm -q "java-${JAVA_VERSION}-openjdk-devel" &>/dev/null; then
    SKIP "Installing Java ${JAVA_VERSION} JDK"
else
    dnf install -y "java-${JAVA_VERSION}-openjdk-devel" \
        >> "$LOGFILE" 2>&1
    VALIDATE $? "Installing Java ${JAVA_VERSION} JDK"
fi

java -version >> "$LOGFILE" 2>&1
VALIDATE $? "Checking Java installation"

javac -version >> "$LOGFILE" 2>&1
VALIDATE $? "Checking Java compiler"

JAVA_HOME_PATH=$(
    dirname "$(dirname "$(readlink -f "$(command -v javac)")")"
)

# ------------------------------------------------------------
# Detect Latest Stable Maven 3.x
# ------------------------------------------------------------

echo
echo "Detecting latest stable Maven 3.x version..."

MAVEN_VERSION=$(
    curl -fsSL "$MAVEN_INDEX_URL" 2>> "$LOGFILE" |
        grep -oP 'href="\K3\.[0-9]+\.[0-9]+(?=/")' |
        sort -Vu |
        tail -n 1
)

if [ -z "$MAVEN_VERSION" ]; then
    echo -e "${R}Unable to detect Maven version.${N}"
    echo "Check URL: $MAVEN_INDEX_URL"
    echo "Check log: $LOGFILE"
    exit 1
fi

echo -e "Latest Maven 3.x Version: ${G}${MAVEN_VERSION}${N}"

# ------------------------------------------------------------
# Maven Paths
# ------------------------------------------------------------

MAVEN_HOME="${MAVEN_BASE_DIR}/apache-maven-${MAVEN_VERSION}"
MAVEN_ARCHIVE="apache-maven-${MAVEN_VERSION}-bin.tar.gz"
MAVEN_URL="${MAVEN_INDEX_URL}${MAVEN_VERSION}/binaries/${MAVEN_ARCHIVE}"

echo "Maven URL  : $MAVEN_URL"
echo "Maven Home : $MAVEN_HOME"
echo

cd "$MAVEN_BASE_DIR" >> "$LOGFILE" 2>&1
VALIDATE $? "Changing directory to $MAVEN_BASE_DIR"

# ------------------------------------------------------------
# Download, Verify and Extract Maven
# ------------------------------------------------------------

if [ -d "$MAVEN_HOME" ]; then
    SKIP "Maven download/extraction"
else
    wget -q "$MAVEN_URL" -O "$MAVEN_ARCHIVE" \
        >> "$LOGFILE" 2>&1
    VALIDATE $? "Downloading Maven"

    EXPECTED_SHA=$(
        curl -fsSL "${MAVEN_URL}.sha512" 2>> "$LOGFILE" |
            awk '{print $1}'
    )

    if [ -z "$EXPECTED_SHA" ]; then
        echo -e "${R}Unable to retrieve Maven SHA512 checksum.${N}"
        exit 1
    fi

    echo "${EXPECTED_SHA}  ${MAVEN_ARCHIVE}" |
        sha512sum -c - >> "$LOGFILE" 2>&1
    VALIDATE $? "Verifying Maven SHA512 checksum"

    tar -xzf "$MAVEN_ARCHIVE" >> "$LOGFILE" 2>&1
    VALIDATE $? "Extracting Maven"

    rm -f "$MAVEN_ARCHIVE"
    VALIDATE $? "Removing Maven archive"
fi

# ------------------------------------------------------------
# Create/Update Maven Symbolic Link
# /opt/maven -> /opt/apache-maven-<version>
# ------------------------------------------------------------

if [ "$(readlink -f "$MAVEN_SYMLINK" 2>/dev/null)" = "$MAVEN_HOME" ]; then
    SKIP "Maven symbolic link"
else
    ln -sfn "$MAVEN_HOME" "$MAVEN_SYMLINK" \
        >> "$LOGFILE" 2>&1
    VALIDATE $? "Creating Maven symbolic link"
fi

# ------------------------------------------------------------
# Configure Permanent Environment Variables
# ------------------------------------------------------------

cat > "$PROFILE_FILE" <<EOF
# Apache Maven and Java
export JAVA_HOME="$JAVA_HOME_PATH"
export M2_HOME="$MAVEN_SYMLINK"
export MAVEN_HOME="$MAVEN_SYMLINK"
export PATH="\$MAVEN_HOME/bin:\$JAVA_HOME/bin:\$PATH"
EOF

VALIDATE $? "Configuring Maven environment variables"

chmod 644 "$PROFILE_FILE"
VALIDATE $? "Setting profile file permissions"

# ------------------------------------------------------------
# FIX: Make mvn Available Immediately for All Users
# ------------------------------------------------------------
# A child script cannot change its parent shell's PATH.
# A symlink in /usr/local/bin makes mvn available without
# requiring the user to run source or log in again.

mkdir -p "$GLOBAL_BIN"
VALIDATE $? "Creating global binary directory"

ln -sfn "$MAVEN_SYMLINK/bin/mvn" "$GLOBAL_BIN/mvn"
VALIDATE $? "Creating global Maven executable link"

chmod +x "$MAVEN_SYMLINK/bin/mvn"
VALIDATE $? "Setting Maven executable permissions"

# ------------------------------------------------------------
# Load Environment in This Script
# ------------------------------------------------------------

source "$PROFILE_FILE"
VALIDATE $? "Loading Maven environment variables"

# ------------------------------------------------------------
# Verify Maven Installation
# ------------------------------------------------------------

"$GLOBAL_BIN/mvn" --version >> "$LOGFILE" 2>&1
VALIDATE $? "Checking Maven installation"

# ------------------------------------------------------------
# Completed
# ------------------------------------------------------------

echo
echo "============================================================"
echo -e "${G} Maven Installation Completed Successfully ${N}"
echo "============================================================"
echo

echo "Java Version:"
java -version

echo
echo "Maven Version:"
mvn --version

echo
echo "Maven Home : $MAVEN_SYMLINK -> $MAVEN_HOME"
echo "Java Home  : $JAVA_HOME_PATH"
echo "Maven Link : $GLOBAL_BIN/mvn"
echo "Log File   : $LOGFILE"
echo
echo "You can run 'mvn --version' immediately."
echo "Environment variables will also load in new login shells."
```
