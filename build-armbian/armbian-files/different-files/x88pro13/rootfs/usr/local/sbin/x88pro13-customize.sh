#!/bin/bash
# x88pro13 image customization: APT -> Tsinghua, docker from the same mirror,
# docker hub registry mirror -> 毫秒镜像 (https://docker.1ms.run).
# Runs either in the build chroot or, as a fallback, on first boot.
set -u

DONE=/var/lib/x88pro13-customize.done
[ -f "$DONE" ] && { echo "already customized"; exit 0; }

export DEBIAN_FRONTEND=noninteractive
LOG=/root/x88pro13-customize.log
mkdir -p /root
exec > >(tee -a "$LOG") 2>&1
echo "== $(date -u) customize start =="

CN="$(. /etc/os-release; echo "${VERSION_CODENAME:-resolute}")"
TS="https://mirrors.tuna.tsinghua.edu.cn"
PORTS="${TS}/ubuntu-ports"

# never let postinst start services while we are inside a chroot
[ -d /run/systemd/system ] || { printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d; chmod +x /usr/sbin/policy-rc.d; }

mkdir -p /tmp/x88-apt-backup
cp -a /etc/apt/sources.list /tmp/x88-apt-backup/ 2>/dev/null || true
cp -a /etc/apt/sources.list.d /tmp/x88-apt-backup/ 2>/dev/null || true

echo "-- apt -> Tsinghua (${PORTS})"
if [ -f /etc/apt/sources.list.d/ubuntu.sources ]; then
	cat > /etc/apt/sources.list.d/ubuntu.sources <<EOF
Types: deb
URIs: ${PORTS}/
Suites: ${CN} ${CN}-updates ${CN}-backports
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
EOF
fi
if [ -f /etc/apt/sources.list ]; then
	sed -i -E "s#https?://[^ /]*(ubuntu\.com|ubuntu-ports)[^ ]*#${PORTS}/#g" /etc/apt/sources.list || true
fi

echo "-- apt-get update"
if ! apt-get update; then
	echo "!! update failed, restoring original sources"
	rm -rf /etc/apt/sources.list.d
	cp -a /tmp/x88-apt-backup/sources.list.d /etc/apt/sources.list.d 2>/dev/null || true
	[ -f /tmp/x88-apt-backup/sources.list ] && cp -a /tmp/x88-apt-backup/sources.list /etc/apt/sources.list
	apt-get update || true
fi

echo "-- install docker"
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
	docker.io docker-compose-v2 ca-certificates curl || \
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
	docker.io ca-certificates curl || true

echo "-- docker hub mirror: docker.1ms.run"
mkdir -p /etc/docker
cat > /etc/docker/daemon.json <<'EOF'
{
  "registry-mirrors": ["https://docker.1ms.run"],
  "log-driver": "json-file",
  "log-opts": { "max-size": "50m", "max-file": "3" }
}
EOF
chmod 644 /etc/docker/daemon.json

mkdir -p /etc/systemd/system/multi-user.target.wants
for u in docker containerd; do
	if [ -f "/lib/systemd/system/${u}.service" ]; then
		ln -sf "/lib/systemd/system/${u}.service" "/etc/systemd/system/multi-user.target.wants/${u}.service"
	fi
done
usermod -aG docker root 2>/dev/null || true

echo "-- cleanup"
rm -f /usr/sbin/policy-rc.d
apt-get clean
rm -rf /var/lib/apt/lists/* /tmp/x88-apt-backup

if command -v docker >/dev/null 2>&1; then
	touch "$DONE"
	echo "docker: $(docker --version 2>/dev/null)"
else
	echo "docker: NOT installed"
fi
echo "== $(date -u) customize done =="
