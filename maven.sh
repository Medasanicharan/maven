#!/bin/bash

# ============================================================
# Maven Installation Script
# ============================================================
# Purpose:
#   Install Java JDK and latest stable Apache Maven 3.x
#
# Software:
#   Java 21
#   Latest Maven 3.x
#
# Installation directory:
#   /opt
#
# ============================================================


# ------------------------------------------------------------
# Configuration
# ------------------------------------------------------------

JAVA_VERSION="21"

MAVEN_BASE_DIR="/opt"
MAVEN_SYMLINK="${MAVEN_BASE_DIR}/maven"

# Maven Central metadata
MAVEN_METADATA_URL="https://repo.maven.apache.org/maven2/org/apache/maven/apache-maven/maven-metadata.xml"

LOGFILE="/tmp/maven-install-$(date +%F-%H-%M-%S).log"


# ------------------------------------------------------------
# Colors
# ------------------------------------------------------------

R="\e[31m"
G="\e[32m"
Y="\e[33m"
N="\e[0m"


# ------------------------------------------------------------
# Function
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
# Start Installation
# ------------------------------------------------------------

echo
echo "============================================================"
echo " Java + Latest Maven 3.x Installation"
echo "============================================================"
echo
echo "Java Version  : $JAVA_VERSION"
echo "Maven Version : Detecting latest stable 3.x..."
echo "Maven Home    : $MAVEN_SYMLINK"
echo "Log File      : $LOGFILE"
echo


# ------------------------------------------------------------
# Update Packages
# ------------------------------------------------------------

echo -e "\nUpdating system packages..."

dnf update -y --allowerasing >>"$LOGFILE" 2>&1
VALIDATE $? "System packages update"


# ------------------------------------------------------------
# Install Required Packages
# ------------------------------------------------------------

dnf install -y wget curl tar gzip &>> "$LOGFILE"

VALIDATE $? "Installing required packages"


# ------------------------------------------------------------
# Install Java JDK
# ------------------------------------------------------------

dnf install -y "java-${JAVA_VERSION}-openjdk-devel" &>> "$LOGFILE"

VALIDATE $? "Installing Java ${JAVA_VERSION} JDK"


# ------------------------------------------------------------
# Verify Java
# ------------------------------------------------------------

java -version &>> "$LOGFILE"

VALIDATE $? "Checking Java installation"


javac -version &>> "$LOGFILE"

VALIDATE $? "Checking Java compiler"


# ------------------------------------------------------------
# Detect Latest Stable Maven 3.x Version
# ------------------------------------------------------------

echo
echo "Detecting latest stable Maven 3.x version..."


MAVEN_VERSION=$(curl -fsSL "$MAVEN_METADATA_URL" \
    | grep -oP '(?<=<version>)[^<]+' \
    | grep -E '^3\.[0-9]+\.[0-9]+$' \
    | sort -V \
    | tail -1)


if [ -z "$MAVEN_VERSION" ]
then

    echo -e "$R Unable to determine latest Maven 3.x version $N"
    echo "Check log file: $LOGFILE"

    exit 1

fi


echo
echo -e "Latest Maven 3.x Version : $G $MAVEN_VERSION $N"
echo


# ------------------------------------------------------------
# Maven Variables
# ------------------------------------------------------------

MAVEN_HOME="${MAVEN_BASE_DIR}/apache-maven-${MAVEN_VERSION}"

MAVEN_ARCHIVE="apache-maven-${MAVEN_VERSION}-bin.tar.gz"

MAVEN_URL="https://dlcdn.apache.org/maven/maven-3/${MAVEN_VERSION}/binaries/${MAVEN_ARCHIVE}"


echo "Maven URL  : $MAVEN_URL"
echo "Maven Home : $MAVEN_HOME"
echo


# ------------------------------------------------------------
# Move to /opt
# ------------------------------------------------------------

cd "$MAVEN_BASE_DIR" &>> "$LOGFILE"

VALIDATE $? "Changing directory to ${MAVEN_BASE_DIR}"


# ------------------------------------------------------------
# Check if Maven Version Already Exists
# ------------------------------------------------------------

if [ -d "$MAVEN_HOME" ]
then

    echo -e "$Y Maven ${MAVEN_VERSION} already exists at ${MAVEN_HOME}... SKIPPING $N"

else

    # --------------------------------------------------------
    # Download Maven
    # --------------------------------------------------------

    echo
    echo "Downloading Maven ${MAVEN_VERSION}..."

    wget -q "$MAVEN_URL" \
        -O "$MAVEN_ARCHIVE" &>> "$LOGFILE"

    VALIDATE $? "Downloading Maven ${MAVEN_VERSION}"


    # --------------------------------------------------------
    # Extract Maven
    # --------------------------------------------------------

    tar -xzf "$MAVEN_ARCHIVE" &>> "$LOGFILE"

    VALIDATE $? "Extracting Maven ${MAVEN_VERSION}"


    # --------------------------------------------------------
    # Remove Archive
    # --------------------------------------------------------

    rm -f "$MAVEN_ARCHIVE" &>> "$LOGFILE"

    VALIDATE $? "Removing Maven archive"

fi


# ------------------------------------------------------------
# Create Stable Maven Symlink
# ------------------------------------------------------------
#
# /opt/maven
#      |
#      v
# /opt/apache-maven-3.9.16
#
# Future:
#
# /opt/maven
#      |
#      v
# /opt/apache-maven-3.9.17
#
# ------------------------------------------------------------

ln -sfn "$MAVEN_HOME" "$MAVEN_SYMLINK" &>> "$LOGFILE"

VALIDATE $? "Creating Maven symbolic link"


# ------------------------------------------------------------
# Configure Environment Variables
# ------------------------------------------------------------

PROFILE_FILE="/etc/profile.d/maven.sh"

cat > "$PROFILE_FILE" <<EOF

# Apache Maven
export M2_HOME="$MAVEN_SYMLINK"
export MAVEN_HOME="$MAVEN_SYMLINK"
export PATH="\$MAVEN_HOME/bin:\$PATH"

EOF

VALIDATE $? "Configuring Maven environment variables"



# # ------------------------------------------------------------
# # Configure Environment Variables
# # ------------------------------------------------------------

# PROFILE_FILE="/etc/profile.d/maven.sh"


# cat > "$PROFILE_FILE" <<EOF

# # Apache Maven

# export M2_HOME="$MAVEN_SYMLINK"
# export MAVEN_HOME="$MAVEN_SYMLINK"
# export PATH="\$M2_HOME/bin:\$PATH"

# EOF


# VALIDATE $? "Configuring Maven environment variables"


# ------------------------------------------------------------
# Load Environment Variables
# ------------------------------------------------------------

source "$PROFILE_FILE" &>> "$LOGFILE"

VALIDATE $? "Loading Maven environment variables"


# ------------------------------------------------------------
# Verify Maven Installation
# ------------------------------------------------------------

mvn -version &>> "$LOGFILE"

VALIDATE $? "Checking Maven installation"


# ------------------------------------------------------------
# Installation Completed
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
echo "Maven Home : $MAVEN_SYMLINK"
echo "Java Home  : $JAVA_HOME"
echo "Log File   : $LOGFILE"