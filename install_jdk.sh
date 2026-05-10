#!/bin/bash

set -e

echo "=============================="
echo " Install Temurin JDK 25"
echo " Debian 13 (trixie)"
echo "=============================="

# 必须 root
if [ "$EUID" -ne 0 ]; then
  echo "请使用 root 运行"
  exit 1
fi

echo
echo ">>> 更新 apt"
apt update

echo
echo ">>> 安装依赖"
apt install -y wget gpg apt-transport-https ca-certificates

echo
echo ">>> 创建 keyrings 目录"
mkdir -p /usr/share/keyrings

echo
echo ">>> 导入 Adoptium GPG Key"
wget -qO - https://packages.adoptium.net/artifactory/api/gpg/key/public \
| gpg --dearmor \
> /usr/share/keyrings/adoptium.gpg

echo
echo ">>> 写入 Adoptium 源"
cat > /etc/apt/sources.list.d/adoptium.list <<EOF
deb [signed-by=/usr/share/keyrings/adoptium.gpg] https://packages.adoptium.net/artifactory/deb trixie main
EOF

echo
echo ">>> 更新 apt"
apt update

echo
echo ">>> 安装 Temurin JDK 25"
apt install -y temurin-25-jdk

echo
echo ">>> Java Version"
java -version

echo
echo "=============================="
echo " JDK 25 安装完成"
echo "=============================="
