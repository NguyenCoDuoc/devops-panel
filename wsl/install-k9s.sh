#!/usr/bin/env bash
# Cài/cập nhật k9s từ GitHub release chính thức (derailed/k9s), có kiểm tra sha256
set -euo pipefail
ARCH=amd64
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
cd "$TMP"
REL=$(curl -fsSL https://api.github.com/repos/derailed/k9s/releases/latest)
VER=$(sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' <<<"$REL" | head -n1 || true)
echo "k9s latest: $VER"
BASE="https://github.com/derailed/k9s/releases/download/$VER"
curl -fsSLO "$BASE/k9s_Linux_${ARCH}.tar.gz"
curl -fsSLO "$BASE/checksums.sha256"
grep " k9s_Linux_${ARCH}.tar.gz\$" checksums.sha256 | sha256sum -c -
tar -xzf "k9s_Linux_${ARCH}.tar.gz" k9s
install -m 0755 k9s /usr/local/bin/k9s
# k9s dùng kubeconfig của k3s
grep -q 'KUBECONFIG=/etc/rancher/k3s/k3s.yaml' /root/.bashrc || echo 'export KUBECONFIG=/etc/rancher/k3s/k3s.yaml' >> /root/.bashrc
k9s version -s
