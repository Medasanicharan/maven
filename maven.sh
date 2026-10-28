#!/bin/bash

# ============================================================
# Maven Installation Script (RHEL 10)
# ============================================================
# Purpose:
#   Install Java JDK and the latest stable Apache Maven 3.x
#   Safe to re-run: steps already done are SKIPPED (yellow).
#
# Optional overrides (environment variables):
#   RUN_SYSTEM_UPDATE=true ./maven-install.sh
# ============================================================


# ------------------------------------------------------------
# Configuration
# ------------------------------------------------------------

JAVA_VERSION="21"

MAVEN_BASE_DIR="/opt"
MAVEN_SYMLINK="${MAVEN_BASE_DIR}/maven"

# Apache directory listing (only holds currently supported releases)
MAVEN_INDEX_URL="https://dlcdn.apache.org/maven/maven-3/"

RUN_SYSTEM_UPDATE="${RUN_SYSTEM_UPDATE:-false}"   # true = run dnf update first

PROFILE_FILE="/etc/profile.d/maven.sh"

LOGFILE="/tmp/maven-install-$(date +%F-%H-%M-%S).log"


# ------------------------------------------------------------
# Colors
# ------------------------------------------------------------

R="\e[31m"
G="\e[32m"
Y="\e[33m"
N="\e[0m"


# ------------------------------------------------------------
# Functions
# ------------------------------------------------------------

VALIDATE() {

    if [ "$1" -ne 0 ]
    then
        echo -e "$2...$R FAILURE $N"
        echo "Check log file: $LOGFILE"
        exit 1
    else
        echo -e "$2...$G SUCCESS $N"
    fi
}

SKIP() {
    echo -e "$1...$Y SKIPPING (already done) $N"
}


# ------------------------------------------------------------
# Root User Check
# ------------------------------------------------------------

USERID=$(id -u)

if [ "$USERID" -ne 0 ]
then
    echo -e "$R Please run this script with root access $N"
    exit 1
else
    echo -e "$G You are running as root $N"
fi


# ------------------------------------------------------------
# Start
# ------------------------------------------------------------

echo
echo "============================================================"
echo " Java + Latest Maven 3.x Installation"
echo "============================================================"
echo
echo "Java Version  : $JAVA_VERSION"
echo "Maven Home    : $MAVEN_SYMLINK"
echo "Log File      : $LOGFILE"
echo


# ------------------------------------------------------------
# System Update (optional)
# ------------------------------------------------------------

if [ "$RUN_SYSTEM_UPDATE" = "true" ]
then
    dnf update -y --allowerasing >> "$LOGFILE" 2>&1
    VALIDATE $? "System packages update"
else
    SKIP "System packages update (RUN_SYSTEM_UPDATE=false)"
fi


# ------------------------------------------------------------
# Required Packages (install only the missing ones)
# ------------------------------------------------------------

MISSING_PKGS=""

for PKG in wget curl tar gzip
do
    rpm -q "$PKG" &>/dev/null || MISSING_PKGS="$MISSING_PKGS $PKG"
done

if [ -z "$MISSING_PKGS" ]
then
    SKIP "Installing required packages"
else
    dnf install -y $MISSING_PKGS &>> "$LOGFILE"
    VALIDATE $? "Installing required packages:${MISSING_PKGS}"
fi


# ------------------------------------------------------------
# Java JDK
# ------------------------------------------------------------

if rpm -q "java-${JAVA_VERSION}-openjdk-devel" &>/dev/null
then
    SKIP "Installing Java ${JAVA_VERSION} JDK"
else
    dnf install -y "java-${JAVA_VERSION}-openjdk-devel" &>> "$LOGFILE"
    VALIDATE $? "Installing Java ${JAVA_VERSION} JDK"
fi

java -version &>> "$LOGFILE"
VALIDATE $? "Checking Java installation"

javac -version &>> "$LOGFILE"
VALIDATE $? "Checking Java compiler"

JAVA_HOME_PATH=$(dirname "$(dirname "$(readlink -f "$(command -v javac)")")")


# ------------------------------------------------------------
# Detect Latest Stable Maven 3.x Version
# ------------------------------------------------------------

echo
echo "Detecting latest stable Maven 3.x version..."

MAVEN_VERSION=$(curl -fsSL "$MAVEN_INDEX_URL" \
    | grep -oP 'href="\K3\.[0-9]+\.[0-9]+(?=/")' \
    | sort -V \
    | tail -1)

if [ -z "$MAVEN_VERSION" ]
then
    echo -e "$R Unable to determine latest Maven 3.x version $N"
    echo "Checked URL: $MAVEN_INDEX_URL"
    exit 1
fi

echo -e "Latest Maven 3.x Version : $G $MAVEN_VERSION $N"

# Show what is currently installed (if anything)
if [ -L "$MAVEN_SYMLINK" ]
then
    CURRENT_HOME=$(readlink -f "$MAVEN_SYMLINK")
    echo -e "Currently installed      : $Y ${CURRENT_HOME##*/apache-maven-} $N"
fi
echo


# ------------------------------------------------------------
# Maven Variables
# ------------------------------------------------------------

MAVEN_HOME="${MAVEN_BASE_DIR}/apache-maven-${MAVEN_VERSION}"
MAVEN_ARCHIVE="apache-maven-${MAVEN_VERSION}-bin.tar.gz"
MAVEN_URL="${MAVEN_INDEX_URL}${MAVEN_VERSION}/binaries/${MAVEN_ARCHIVE}"

echo "Maven URL  : $MAVEN_URL"
echo "Maven Home : $MAVEN_HOME"
echo

cd "$MAVEN_BASE_DIR" &>> "$LOGFILE"
VALIDATE $? "Changing directory to ${MAVEN_BASE_DIR}"


# ------------------------------------------------------------
# Download + Verify + Extract (skip if this version exists)
# ------------------------------------------------------------

if [ -d "$MAVEN_HOME" ]
then

    SKIP "Maven ${MAVEN_VERSION} download/extract (found at ${MAVEN_HOME})"

else

    wget -q "$MAVEN_URL" -O "$MAVEN_ARCHIVE" &>> "$LOGFILE"
    VALIDATE $? "Downloading Maven ${MAVEN_VERSION}"

    # Apache publishes only the hash in the .sha512 file
    EXPECTED_SHA=$(curl -fsSL "${MAVEN_URL}.sha512" | awk '{print $1}')
    echo "${EXPECTED_SHA}  ${MAVEN_ARCHIVE}" | sha512sum -c - &>> "$LOGFILE"
    VALIDATE $? "Verifying SHA512 checksum"

    tar -xzf "$MAVEN_ARCHIVE" &>> "$LOGFILE"
    VALIDATE $? "Extracting Maven ${MAVEN_VERSION}"

    rm -f "$MAVEN_ARCHIVE" &>> "$LOGFILE"
    VALIDATE $? "Removing Maven archive"

fi


# ------------------------------------------------------------
# Symlink  /opt/maven -> /opt/apache-maven-<version>
# ------------------------------------------------------------

if [ "$(readlink -f "$MAVEN_SYMLINK" 2>/dev/null)" = "$MAVEN_HOME" ]
then
    SKIP "Creating Maven symbolic link (already points to ${MAVEN_HOME})"
else
    ln -sfn "$MAVEN_HOME" "$MAVEN_SYMLINK" &>> "$LOGFILE"
    VALIDATE $? "Creating Maven symbolic link"
fi


# ------------------------------------------------------------
# Environment Variables
# ------------------------------------------------------------

if [ -f "$PROFILE_FILE" ] && grep -q "MAVEN_HOME=\"$MAVEN_SYMLINK\"" "$PROFILE_FILE"
then
    SKIP "Configuring Maven environment variables"
else
    cat > "$PROFILE_FILE" <<EOF

# Apache Maven
export M2_HOME="$MAVEN_SYMLINK"
export MAVEN_HOME="$MAVEN_SYMLINK"
export PATH="\$MAVEN_HOME/bin:\$PATH"

EOF
    VALIDATE $? "Configuring Maven environment variables"
fi

source "$PROFILE_FILE" &>> "$LOGFILE"
VALIDATE $? "Loading Maven environment variables"


# ------------------------------------------------------------
# Verify Maven
# ------------------------------------------------------------

mvn -version &>> "$LOGFILE"
VALIDATE $? "Checking Maven installation"


# ------------------------------------------------------------
# Completed
# ------------------------------------------------------------

echo
echo "============================================================"
echo -e "$G Maven Installation Completed Successfully $N"
echo "============================================================"
echo

echo "Java Version:"
java -version

echo
echo "Maven Version:"
mvn -version

echo
echo "Maven Home : $MAVEN_SYMLINK  ->  $MAVEN_HOME"
echo "Java Home  : $JAVA_HOME_PATH"
echo "Log File   : $LOGFILE"
echo
echo "Run 'source $PROFILE_FILE' (or log in again) to use mvn in your current shell."