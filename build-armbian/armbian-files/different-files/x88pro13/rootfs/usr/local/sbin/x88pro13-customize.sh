#!/bin/bash
# x88pro13 image customization, runs inside the staged rootfs (chroot) at build time.
#   1) APT -> Tsinghua (ubuntu-ports for arm64)
#   2) install docker (docker.io + compose v2) from that mirror
#   3) docker hub registry mirror -> 毫秒镜像 (https://docker.1ms.run)
set -u

export DEBIAN_FRONTEND=noninteractive
LOG=/root/x88pro13-customize.log
exec > >(tee -a "$LOG") 2>&1
echo "== $(date -u) customize start =="

. /etc/os-release
CN="${VERSION_CODENAME:-resolute}"
TS="https://mirrors.tuna.tsinghua.edu.cn"
PORTS="${TS}/ubuntu-ports"

# don't let postinst start services inside the chroot
printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d
chmod +x /usr/sbin/policy-rc.d

echo "-- backup apt sources"
mkdir -p /tmp/x88-apt-backup
cp -a /etc/apt/sources.list /tmp/x88-apt-backup/ 2>/dev/null || true
cp -a /etc/apt/sources.list.d /tmp/x88-apt-backup/ 2>/dev/null || true

echo "-- point apt at Tsinghua"
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
	echo "!! Tsinghua apt update failed, restoring original sources"
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

echo "-- docker daemon config (hub mirror: docker.1ms.run)"
mkdir -p /etc/docker
cat > /etc/docker/daemon.json <<'EOF'
{
  "registry-mirrors": ["https://docker.1ms.run"],
  "log-driver": "json-file",
  "log-opts": { "max-size": "50m", "max-file": "3" }
}
EOF
chmod 644 /etc/docker/daemon.json

# enable at boot without needing dbus inside the chroot
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

echo "-- versions"
(docker --version 2>/dev/null || echo "docker: not installed")
(dpkg -l docker.io 2>/dev/null | tail -1) || true
echo "== $(date -u) customize done =="
