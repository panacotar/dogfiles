#!/bin/bash

# Source: https://gist.github.com/BaksiLi/ea2f505fdbe42349a5225390264c1f40

# Get the architecture of the machine
arch=$(uname -m)
os=$(uname -s)

# Download the Zellij binary
if [ "$os" == "Darwin" ]; then
  filename="zellij-${arch}-apple-darwin.tar.gz"
  url="https://github.com/zellij-org/zellij/releases/latest/download/$filename"
  echo "Downloading Zellij binary for macOS..."
  curl -LO "$url"
else
  if [ "$os" == "Linux" ]; then
    filename="zellij-${arch}-unknown-linux-musl.tar.gz"
    url="https://github.com/zellij-org/zellij/releases/latest/download/$filename"
    echo "Downloading Zellij binary for Linux..."
    curl -LO "$url"
  else
    echo "Unsupported OS: $os"
  fi
fi

# Uncompress the Zellij binary
echo "Uncompressing Zellij binary..."
tar -xf "$filename" --directory=./zellij

# Move the Zellij binary to the /bin directory
echo "Moving Zellij binary to /bin directory..."
sudo mv ./zellij/zellij /bin/zellij

# Remove the .tar.gz file
echo "Removing .tar.gz file..."
rm "$filename"

# Check if the Zellij binary exists
if [ -f "/bin/zellij" ]; then
  echo "Zellij binary installed successfully!"
else
  echo "Zellij binary not installed successfully!"
fi