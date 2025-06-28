#!/bin/bash
# Test script to reproduce the issue

echo "Testing line 179 issue..."
echo

# Confirmation prompt
read -p "Proceed with Samba setup? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Setup cancelled"
    exit 0
fi

echo "No error occurred"