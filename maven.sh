#!/bin/bash

# ============================================================
# Java 21 + Latest Stable Apache Maven 3.x
# Operating System: RHEL 10
# ============================================================

set -o pipefail

# ------------------------------------------------------------
# Configuration
# ------------------------------------------------------------

JAVA_VERSION="21"

MAVEN_BASE_DIR="/opt"
MAVEN_SYMLINK="/opt/maven"
PROFILE_FILE="/etc/profile.d/maven.sh"
GLOBAL_BIN="/usr/local/bin"
MAVEN_INDEX_URL="https://dlcdn.apache.org/maven/maven-3/"
RUN_SYSTEM_UPDATE="${RUN_SYSTEM_UPDATE:-false}"

LOGFILE="/tmp/maven-install-$(date +%F-%H-%M-%S).log"

# ------------------------------------------------------------
# Functions
# ------------------------------------------------------------

VALIDATE() {
    local STATUS="$1"
    local MESSAGE="$2"

    if [ "$STATUS" -eq 0 ]; then
        echo "$MESSAGE... SUCCESS"
    else
        echo "$MESSAGE... FAILURE"
        echo "Check log file: $LOGFILE"
        exit 1
    fi
}

SKIP() {
    echo "$1... SKIPPING (already done)"
}

# ------------------------------------------------------------
# Root Check
# ------------------------------------------------------------

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: Run this script with root access."
    echo "Command: sudo bash maven.sh"
    exit 1
fi

touch "$LOGFILE" || {
    echo "ERROR: Cannot create log file."
    exit 1
}

echo
echo "============================================================"
echo " Java + Latest Maven 3.x Installation"
echo "============================================================"
echo
echo "Java Version : $JAVA_VERSION"
echo "Maven Home   : $MAVEN_SYMLINK"
echo "Log File     : $LOGFILE"
echo

# ------------------------------------------------------------
# Optional System Update
# ------------------------------------------------------------

if [ "$RUN_SYSTEM_UPDATE" = "true" ]; then
    dnf update -y --allowerasing >> "$LOGFILE" 2>&1
    VALIDATE $? "System package update"
else
    SKIP "System package update"
fi

# ------------------------------------------------------------
# Required Packages
# ------------------------------------------------------------

MISSING_PKGS=""

for PKG in wget curl tar gzip
do
    if ! rpm -q "$PKG" >/dev/null 2>&1; then
        MISSING_PKGS="$MISSING_PKGS $PKG"
    fi
done

if [ -n "$MISSING_PKGS" ]; then
    dnf install -y $MISSING_PKGS >> "$LOGFILE" 2>&1
    VALIDATE $? "Installing required packages"
else
    SKIP "Required packages"
fi

# ------------------------------------------------------------
# Install Java 21 JDK
# ------------------------------------------------------------

if rpm -q "java-${JAVA_VERSION}-openjdk-devel" >/dev/null 2>&1; then
    SKIP "Java ${JAVA_VERSION} JDK"
else
    dnf install -y "java-${JAVA_VERSION}-openjdk-devel" \
        >> "$LOGFILE" 2>&1
    VALIDATE $? "Installing Java ${JAVA_VERSION} JDK"
fi

JAVAC_PATH=$(command -v javac)

if [ -z "$JAVAC_PATH" ]; then
    echo "ERROR: javac was not found."
    exit 1
fi

JAVA_HOME_PATH=$(dirname "$(dirname "$(readlink -f "$JAVAC_PATH")")")

if [ ! -x "$JAVA_HOME_PATH/bin/java" ]; then
    echo "ERROR: Java executable not found under $JAVA_HOME_PATH"
    exit 1
fi

export JAVA_HOME="$JAVA_HOME_PATH"
export PATH="$JAVA_HOME/bin:$PATH"

"$JAVA_HOME/bin/java" -version >> "$LOGFILE" 2>&1
VALIDATE $? "Checking Java installation"

"$JAVA_HOME/bin/javac" -version >> "$LOGFILE" 2>&1
VALIDATE $? "Checking Java compiler"

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
    echo "ERROR: Could not detect the latest Maven 3.x version."
    echo "URL: $MAVEN_INDEX_URL"
    echo "Check log: $LOGFILE"
    exit 1
fi

echo "Latest Maven 3.x Version: $MAVEN_VERSION"

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
VALIDATE $? "Changing to $MAVEN_BASE_DIR"

# ------------------------------------------------------------
# Download, Verify and Extract Maven
# ------------------------------------------------------------

if [ -d "$MAVEN_HOME" ]; then
    SKIP "Maven $MAVEN_VERSION download and extraction"
else
    wget -q "$MAVEN_URL" -O "$MAVEN_ARCHIVE" \
        >> "$LOGFILE" 2>&1
    VALIDATE $? "Downloading Maven"

    EXPECTED_SHA=$(
        curl -fsSL "${MAVEN_URL}.sha512" 2>> "$LOGFILE" |
            awk '{print $1}'
    )

    if [ -z "$EXPECTED_SHA" ]; then
        echo "ERROR: Could not retrieve the Maven SHA512 checksum."
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
# Validate Maven Executable
# ------------------------------------------------------------

if [ ! -x "$MAVEN_HOME/bin/mvn" ]; then
    echo "ERROR: Maven executable not found:"
    echo "$MAVEN_HOME/bin/mvn"
    exit 1
fi

# ------------------------------------------------------------
# Create Stable Maven Symlink
# /opt/maven -> /opt/apache-maven-<version>
# ------------------------------------------------------------

if [ -e "$MAVEN_SYMLINK" ] && [ ! -L "$MAVEN_SYMLINK" ]; then
    echo "ERROR: $MAVEN_SYMLINK exists and is not a symbolic link."
    echo "Inspect it before replacing anything."
    exit 1
fi

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

VALIDATE $? "Configuring environment variables"

chmod 644 "$PROFILE_FILE"
VALIDATE $? "Setting profile permissions"

# ------------------------------------------------------------
# Make Maven Available Immediately to All Users
# ------------------------------------------------------------

mkdir -p "$GLOBAL_BIN"
VALIDATE $? "Creating global binary directory"

ln -sfn "$MAVEN_SYMLINK/bin/mvn" "$GLOBAL_BIN/mvn"
VALIDATE $? "Creating global Maven command"

# ------------------------------------------------------------
# Load Environment in the Installation Process
# ------------------------------------------------------------

source "$PROFILE_FILE"
VALIDATE $? "Loading environment variables"

# ------------------------------------------------------------
# Verify Maven Installation
# ------------------------------------------------------------

"$MAVEN_SYMLINK/bin/mvn" --version >> "$LOGFILE" 2>&1
VALIDATE $? "Checking Maven installation"

# ------------------------------------------------------------
# Installation Summary
# ------------------------------------------------------------

echo
echo "============================================================"
echo " Maven Installation Completed Successfully"
echo "============================================================"
echo

echo "Java Version:"
"$JAVA_HOME/bin/java" -version

echo
echo "Maven Version:"
"$MAVEN_SYMLINK/bin/mvn" --version

echo
echo "Maven Home : $MAVEN_SYMLINK"
echo "Java Home  : $JAVA_HOME_PATH"
echo "Maven Link : $GLOBAL_BIN/mvn"
echo "Log File   : $LOGFILE"
echo
echo "Run mvn --version from your current shell."
echo "New login shells will load /etc/profile.d/maven.sh."
