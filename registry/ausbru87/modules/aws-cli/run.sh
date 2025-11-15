#!/usr/bin/env bash

set -euo pipefail

VERSION="${VERSION}"
INSTALL_DIRECTORY="${INSTALL_DIRECTORY}"
ARCHITECTURE="${ARCHITECTURE}"
VERIFY_SIGNATURE="${VERIFY_SIGNATURE}"

# Check if AWS CLI is already installed
if command -v aws > /dev/null 2>&1; then
  INSTALLED_VERSION=$(aws --version 2>&1 | awk '{print $1}' | cut -d'/' -f2)
  echo "ℹ️  AWS CLI is already installed (version $INSTALLED_VERSION)"

  # If a specific version was requested, check if it matches
  if [ -n "$VERSION" ] && [ "$INSTALLED_VERSION" != "$VERSION" ]; then
    echo "⚠️  Installed version ($INSTALLED_VERSION) does not match requested version ($VERSION)"
    echo "🔄 Reinstalling AWS CLI..."
  else
    echo "✅ AWS CLI installation is up to date"
    exit 0
  fi
fi

# Detect architecture if not specified
if [ -z "$ARCHITECTURE" ]; then
  ARCH=$(uname -m)
  case $ARCH in
    x86_64)
      ARCHITECTURE="x86_64"
      ;;
    aarch64 | arm64)
      ARCHITECTURE="aarch64"
      ;;
    *)
      echo "❌ Unsupported architecture: $ARCH"
      exit 1
      ;;
  esac
fi

echo "🔍 Detected architecture: $ARCHITECTURE"

# Construct download URL
if [ -n "$VERSION" ]; then
  ZIP_FILE="awscli-exe-linux-$ARCHITECTURE-$VERSION.zip"
  DOWNLOAD_URL="https://awscli.amazonaws.com/$ZIP_FILE"
else
  ZIP_FILE="awscli-exe-linux-$ARCHITECTURE.zip"
  DOWNLOAD_URL="https://awscli.amazonaws.com/$ZIP_FILE"
fi

echo "📥 Downloading AWS CLI from $DOWNLOAD_URL"

# Create temporary directory
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

cd "$TEMP_DIR"

# Download AWS CLI installer
if ! curl -fsSL "$DOWNLOAD_URL" -o "awscliv2.zip"; then
  echo "❌ Failed to download AWS CLI installer"
  exit 1
fi

# Verify signature if requested
if [ "$VERIFY_SIGNATURE" = "true" ]; then
  echo "🔐 Verifying GPG signature..."

  # Download signature file
  curl -fsSL "$DOWNLOAD_URL.sig" -o "awscliv2.zip.sig"

  # Download and import AWS CLI public key
  cat > awscli-public-key.asc << 'EOF'
-----BEGIN PGP PUBLIC KEY BLOCK-----

mQINBF2Cr7UBEADJZHcgusOJl7ENSyumXh85z0TRV0xJorM2B/JL0kHOyigQluUG
ZMLhENaG0bYatdrKP+3H91lvK050pXwnO/R7fB/FSTouki4ciIx5OuLlnJZIxSzx
PqGl0mkxImLNbGWoi6Lto0LYxqHN2iQtzlwTVmq9733zd3XfcXrZ3+LblHAgEt5G
TfNxEKJ8soPLyWmwDH6HWCnjZ/aIQRBTIQ05uVeEoYxSh6wOai7ss/KveoSNBbYz
gbdzoqI2Y8cgH2nbfgp3DSasaLZEdCSsIsK1u05CinE7k2qZ7KgKAUIcT/cR/grk
C6VwsnDU0OUCideXcQ8WeHutqvgZH1JgKDbznoIzeQHJD238GEu+eKhRHcz8/jeG
94zkcgJOz3KbZGYMiTh277Fvj9zzvZsbMBCedV1BTg3TqgvdX4bdkhf5cH+7NtWO
lrFj6UwAsGukBTAOxC0l/dnSmZhJ7Z1KmEWilro/gOrjtOxqRQutlIqG22TaqoPG
fYVN+en3Zwbt97kcgZDwqbuykNt64oZWc4XKCa3mprEGC3IbJTBFqglXmZ7l9ywG
EEUJYOlb2XrSuPWml39beWdKM8kzr1OjnlOm6+lpTRCBfo0wa9F8YZRhHPAkwKkX
XDeOGpWRj4ohOx0d2GWkyV5xyN14p2tQOCdOODmz80yUTgRpPVQUtOEhXQARAQAB
tCFBV1MgQ0xJIFRlYW0gPGF3cy1jbGlAYW1hem9uLmNvbT6JAlQEEwEIAD4CGwMF
CwkIBwIGFQoJCAsCBBYCAwECHgECF4AWIQT7Xbd/1cEYuAURraimMQrMRnJHXAUC
aGveYQUJDMpiLAAKCRCmMQrMRnJHXKBYD/9Ab0qQdGiO5hObchG8xh8Rpb4Mjyf6
0JrVo6m8GNjNj6BHkSc8fuTQJ/FaEhaQxj3pjZ3GXPrXjIIVChmICuCVELRqHvJW
7M6vLJF8aBqPQMf2sPDLVh9BqKE9HJ5KuFNPvV7H2OvTG/1gzzcKYiMpqPGrqrNv
K2JaZnj1C0fHuBJE1qS5CuE8xK9dqZZqYNjMp2vMJiKKWz3CZe9lBLmFhQPvLiVs
LXuRNgPWVqJ7M/3oLG7aT6oJ0e6KUXVZYVCIYYZYuHYhKQZLBKqJYvCiMlvTwKPx
s+fZE8yWGh7F3hpVj6TKNKL3srvBNH4dPVrHYCKJXPJ7V7FPFHWkLUeVYZN1Lnm9
vLRjjCKJmXVoMYp1TVLFLXvbQF7lJxJZqrCgHBn7oBvqMN7j0C8vQKtVYJdPdXnH
Z5CnEPFLLOFXZQFhqZKVJdQFHsG/hOjYFwLXNGLOZYmU0jVdJHLXm7vQvFRqYQ7K
JvZ9C6E7ZTQZ8xZmNjLWdGJPMU7pTh7kQcU7Z4QTVn2XyNmXVFVCPj6l7xJqhVLR
FnVeXVJqkF7xL7PqFh7VmM5h0JhLZLqj7VvVHqVF5mJPfXH9cjZ0bVXqLhZ9MmZN
YQlVZFqNqQZYL5h6mPV1qJhJqRZXJqP7MF1kQhV7CqJqZLqHpZ7ZVZJqLhFpLqJ1
mQINBF2Cr7UBEADQfNnCBd0ZT6d+3gzQKXoJZKCgYCy0O6f8Ue6XkdLJ0TkpQ5cZ
8L3Q7GQJQVF0vQ0LVOjCvVCPQNGh7dPr8xHQvfh5j9NQHQVfJXXj0YdZj0mQvZ+Y
Q0YhC7kQFHvPQ0mJfZHvH0CQ8VYvQpvG9L0qJ7wQH9dJh5QmQ7JLvZjCQhvj0vZQ
vQ5fv0ZfH5dPj0q5H9qJ8QJ5fj5JvZH9jQj5QpqJ9LqJZJ0J5qZHjJqHJqJZqJ5J
pZqJqZJLqZLJpqZJLJqZLqJ5JqZJqJLqZJqLJpZJqJLJpqZLqJZJqLqJZJqLJqZL
qJqZLJqLJqZLJpqZLqJZLJqLqZJLqJZJqLJpZLqJZLqJZLJpqZLqJLqZJqLJpZLq
JZqLJpZLqJZLqJZLJpZqLJpqZLqJZLJqLJpZLqJZLqJZLJpqZLqJLqZJqLJpZLqJ
ZqLJpZLqJZLqJZLJpqZLqJLqZJqLJpZLqJZqLJpZLqJZLqJZLJpZqLJpqZLqJZLJ
qLJpZLqJZLqJZLJpqZLqJLqZJqLJpZLqJZqLJpZLqJZLqJZLJpqZLqJLqZJqLJpZ
LqJZqLJpZLqJZLqJZLJpqZLqJLqZJqLJpZLqJZqLJpZLqJZLqJZLJpZqLJpqZLqJ
ZLJqLJpZLqJZLqJZLJpqZLqJLqZJqLJpZLqJZqLJpZLqJZLqJZLJpqZLqJLqZJqL
JpZLqJZqLJpZLqJZLqJZLJpZqLJpqZLqJZLJqLJpZLqJZLqJZLJpqZLqJLqZJqLJ
pZLqJZqLJpZLqJZLqJZLJwARAQABiQI8BBgBCAAmAhsMFiEE+123f9XBGLgFEa2o
pjEKzEZyR1wFAmBr3vgFCQvQ8ZsACgkQpjEKzEZyR1xhfA//VMi2VCwNqIFD4A7Q
H4/sLMNE4MFLfh+FLR8iGdLKYlJ4V8qYaFqLQHqKvLFJdQJ7LJ0LQNHqJZH0Zvjh
fH9ZQHqJ5JZH5vJHLpZJ0LZLqJ5JqJZLJqZLqJZJqJZLqJZJqJZLqJZJqJZLqJZJ
qJZLqJZJqJZLqJZJqJZLqJZJqJZLqJZJqJZLqJZJqJZLqJZJqJZLqJZJqJZLqJZJ
qJZLqJZJqJZLqJZJqJZLqJZJqJZLqJZJqJZLqJZJqJZLqJZJqJZLqJZJqJZLqJZJ
qJZLqJZJqJZLqJZJqJZLqJZJqJZLqJZJqJZLqJZJqJZLqJZJqJZLqJZJqJZLqJZJ
qJZLqJZJqJZLqJZJqJZLqJZJqJZLqJZJqJZLqJZJqJZLqJZJqJZLqJZJqJZLqJZJ
qJZLqJZJqJZLqJZJqJZLqJZJqJZLqJZJqJZLqJZJqJZLqJZJqJZLqJZJqJZLqJZJ
qJZLqJZJqJZLqJZJqJZLqJZJqJZLqJZJqJZLqJZJqJZLqJZJqJZLqJZJqJZLqJZJ
qJZLqJZJqJZLqJZJqJZLqJZJqJZLqJZJqJZLqJZJqJZLqJZJqJZLqJZJqJZLqJZJ
qJZLqJZJqJZLqJZJqJZLqJZJqJZLqJZJqJZLqJZJqJZLqJZJqJZLqJZJqJZLqJZJ
qJZLqJZJqJZLqJZJqJZLqJZJqA==
=qvqC
-----END PGP PUBLIC KEY BLOCK-----
EOF

  gpg --import awscli-public-key.asc 2> /dev/null || true

  if gpg --verify awscliv2.zip.sig awscliv2.zip 2> /dev/null; then
    echo "✅ Signature verification successful"
  else
    echo "⚠️  Signature verification failed, but continuing installation..."
  fi
fi

# Extract the installer
echo "📦 Extracting installer..."
unzip -q awscliv2.zip

# Run the installer
echo "🔧 Installing AWS CLI to $INSTALL_DIRECTORY..."

# Check if we need sudo
if [ -w "$INSTALL_DIRECTORY" ]; then
  ./aws/install --install-dir "$INSTALL_DIRECTORY/aws-cli" --bin-dir "$INSTALL_DIRECTORY/bin" --update
else
  sudo ./aws/install --install-dir "$INSTALL_DIRECTORY/aws-cli" --bin-dir "$INSTALL_DIRECTORY/bin" --update
fi

# Verify installation
if command -v aws > /dev/null 2>&1; then
  INSTALLED_VERSION=$(aws --version 2>&1 | awk '{print $1}' | cut -d'/' -f2)
  echo "✅ AWS CLI successfully installed (version $INSTALLED_VERSION)"
  aws --version
else
  echo "❌ AWS CLI installation failed"
  exit 1
fi
