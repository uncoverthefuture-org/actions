#!/usr/bin/env bash
# install-apache.sh - Install Apache2 web server
set -euo pipefail

echo "🔧 Starting Apache2 installation ..."
echo "📥 Updating apt cache ..."
apt-get update -y
echo "📦 Installing apache2 and mod_wsgi ..."
apt-get install -y apache2 libapache2-mod-wsgi-py3

echo "✅ Apache2 installed"
echo "🔎 apache2 -v"
apache2 -v
