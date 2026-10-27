#!/bin/bash
# x88pro13 image customization - runs inside the staged rootfs (chroot) at build time.
#   1) root password fixed, no forced change / first-login wizard
#   2) docker + compose from the image's official apt sources
#   3) nezha agent baked in (works offline on first boot)
# Everything here leaves no trace: the caller removes this script afterwards.
set -u
export DEBIAN_FRONTEND=noninteractive
umask 022

# ---------- 1) login policy ----------
echo 'root:hao123.com@@@' | chpasswd
passwd -u root >/dev/null 2>&1 || true
chage -d "$(date +%F)" -m 0 -M 99999 -I -1 -E -1 root 2>/dev/null || true
rm -f /root/.not_logged_in_yet
rm -f /etc/profile.d/armbian-check-first-login.sh /etc/profile.d/armbian-check-first-login-reboot.sh
rm -f /usr/lib/armbian/armbian-firstlogin /etc/armbian-firstlogin 2>/dev/null || true

# ---------- chroot only: resolver + no service start ----------
if [ ! -d /run/systemd/system ]; then
	printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d
	chmod +x /usr/sbin/policy-rc.d
	rm -f /etc/resolv.conf
	printf 'nameserver 8.8.8.8\nnameserver 1.1.1.1\n' > /etc/resolv.conf
fi

# ---------- 2) docker ----------
apt-get update >/dev/null 2>&1 || true
apt-get install -y --no-install-recommends docker.io docker-compose-v2 ca-certificates curl unzip >/dev/null 2>&1 || \
apt-get install -y --no-install-recommends docker.io ca-certificates curl unzip >/dev/null 2>&1 || true

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
	[ -f "/lib/systemd/system/${u}.service" ] && \
		ln -sf "/lib/systemd/system/${u}.service" "/etc/systemd/system/multi-user.target.wants/${u}.service"
done
usermod -aG docker root 2>/dev/null || true

# ---------- 3) nezha agent (offline, baked in) ----------
NZ_DIR=/opt/nezha/agent
mkdir -p "$NZ_DIR"
if curl -fsSL --max-time 120 -o /tmp/nz.zip \
	https://github.com/nezhahq/agent/releases/latest/download/nezha-agent_linux_arm64.zip; then
	unzip -qo /tmp/nz.zip -d "$NZ_DIR" && rm -f /tmp/nz.zip
	chmod +x "$NZ_DIR/nezha-agent"
	cat > "$NZ_DIR/config.yml" <<'EOF'
client_secret: rubFos1woDjK3nMsyNQ9qy1yG6GcGZHv
debug: false
disable_auto_update: true
disable_command_execute: false
disable_force_update: true
disable_nat: false
disable_send_query: false
gpu: false
insecure_tls: true
ip_report_period: 1800
report_delay: 4
server: ops.118.im:443
skip_connection_count: false
skip_procs_count: false
temperature: false
tls: true
use_gitee_to_upgrade: false
use_ipv6_country_code: false
EOF
	chmod 600 "$NZ_DIR/config.yml"
	cat > /etc/systemd/system/nezha-agent.service <<'EOF'
[Unit]
Description=Nezha Agent
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStart=/opt/nezha/agent/nezha-agent -c /opt/nezha/agent/config.yml
Restart=always
RestartSec=10
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF
	chmod 644 /etc/systemd/system/nezha-agent.service
	ln -sf /etc/systemd/system/nezha-agent.service \
		/etc/systemd/system/multi-user.target.wants/nezha-agent.service
fi

# ---------- 4) wipe traces ----------
apt-get purge -y unzip >/dev/null 2>&1 || true
apt-get clean >/dev/null 2>&1 || true
rm -rf /var/lib/apt/lists/* /tmp/nz.zip /tmp/nezha*
rm -f /usr/sbin/policy-rc.d /root/.bash_history /root/.viminfo
rm -f /etc/systemd/system/x88pro13-customize.service
rm -f /etc/systemd/system/multi-user.target.wants/x88pro13-customize.service
rm -f /var/lib/x88pro13-customize.done /root/x88pro13-customize.log
if [ ! -d /run/systemd/system ]; then
	rm -f /etc/resolv.conf
	ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
fi
exit 0

