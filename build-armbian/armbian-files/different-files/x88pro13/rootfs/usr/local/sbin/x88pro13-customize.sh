#!/bin/bash
# x88pro13 image customization: install docker from the image's own (official) apt
# sources and point docker hub at 毫秒镜像 (https://docker.1ms.run).
# Runs in the build chroot, or on first boot as a fallback.
set -u

DONE=/var/lib/x88pro13-customize.done
[ -f "$DONE" ] && { echo "already customized"; exit 0; }

export DEBIAN_FRONTEND=noninteractive
LOG=/root/x88pro13-customize.log
mkdir -p /root
exec > >(tee -a "$LOG") 2>&1
echo "== $(date -u) customize start =="

# inside a chroot there is no systemd-resolved: give apt a working resolver
RESOLV_LINK=/run/systemd/resolve/stub-resolv.conf
if [ ! -d /run/systemd/system ]; then
	printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d
	chmod +x /usr/sbin/policy-rc.d
	if [ -L /etc/resolv.conf ] || [ ! -s /etc/resolv.conf ]; then
		rm -f /etc/resolv.conf
		printf 'nameserver 8.8.8.8\nnameserver 1.1.1.1\nnameserver 223.5.5.5\n' > /etc/resolv.conf
		echo "-- temporary resolv.conf for chroot: $(tr '\n' ' ' < /etc/resolv.conf)"
	fi
fi

echo "-- apt sources (unchanged, official)"
grep -h -E '^(URIs|deb )' /etc/apt/sources.list.d/*.sources /etc/apt/sources.list 2>/dev/null | head -5

echo "-- apt-get update"
apt-get update || apt-get update || true

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
rm -rf /var/lib/apt/lists/*

# restore the image's original resolver handling
if [ ! -d /run/systemd/system ]; then
	rm -f /etc/resolv.conf
	ln -sf "$RESOLV_LINK" /etc/resolv.conf
	echo "-- resolv.conf restored -> $RESOLV_LINK"
fi

if command -v docker >/dev/null 2>&1; then
	touch "$DONE"
	echo "docker: $(docker --version 2>/dev/null)"
else
	echo "docker: NOT installed"
fi
echo "== $(date -u) customize done =="
