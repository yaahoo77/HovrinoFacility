#!/bin/bash
# Phone Game (simple version): installs everything on an Ubuntu server, clean or with Asterisk already on it.
#   sudo bash install.sh            shows what it will do and asks once
#   sudo bash install.sh --yes      no questions
# Your existing Asterisk config is backed up first; the game only adds its own files.
set -euo pipefail
cd "$(dirname "$0")"

say()  { printf '\n\033[1m%s\033[0m\n' "$*"; }
fail() { printf '\n\033[31mProblem: %s\033[0m\n' "$*" >&2; exit 1; }

[ "$(id -u)" = 0 ] || fail "Run it with sudo:  sudo bash install.sh"
command -v apt-get >/dev/null || fail "This installer needs Ubuntu (or another system with apt)."

ETC=/etc/asterisk
WEBROOT=/var/www/html
STAMP=$(date +%Y%m%d-%H%M%S)
HAS_SYSTEMD=0; [ -d /run/systemd/system ] && HAS_SYSTEMD=1

cat <<INFO
This installs the Phone Game on this server. It will:
  1. install Asterisk, Apache and PHP if they are missing (apt)
  2. back up $ETC (to $ETC.backup-$STAMP) if it exists
  3. restore Asterisk's standard config files if any are missing, and add a SIP port (UDP 5060) if there is none
     (this restarts Asterisk once; calls in progress would be cut)
  4. add the game: phone line 6001, the story, the 3 sounds, the /documentation trigger
  5. copy the website from site/ to $WEBROOT (if site/ has one)
  6. if the ufw firewall is on: allow SIP (5060/udp), audio (10000-20000/udp) and the website (80/tcp)
INFO
if [ "${1:-}" != "--yes" ]; then
  read -r -p "Continue? [y/N] " a
  case "$a" in y|Y|yes) ;; *) echo "Nothing changed."; exit 0 ;; esac
fi

# ---------- 1. packages ----------
say "1/6 Installing Asterisk, Apache and PHP (this can take a few minutes)"
export DEBIAN_FRONTEND=noninteractive
NEED=()
for p in asterisk asterisk-core-sounds-en apache2 php libapache2-mod-php; do
  dpkg -s "$p" >/dev/null 2>&1 || NEED+=("$p")
done
if [ ${#NEED[@]} -gt 0 ]; then
  apt-get update -qq || fail "apt-get update failed. Is the server online?"
  apt-get install -y -qq "${NEED[@]}" >/dev/null || fail "Installing ${NEED[*]} failed (see the messages above)."
fi
echo "OK"

start_service() { # start_service <name>
  if [ "$HAS_SYSTEMD" = 1 ]; then systemctl enable -q "$1" 2>/dev/null || true; systemctl restart "$1"
  else service "$1" restart >/dev/null 2>&1 || service "$1" start >/dev/null 2>&1 || true; fi
}
asterisk_up() { asterisk -rx "core show version" >/dev/null 2>&1; }
restart_asterisk() {
  if [ "$HAS_SYSTEMD" = 1 ]; then systemctl enable -q asterisk 2>/dev/null || true; systemctl restart asterisk
  else
    asterisk_up && { asterisk -rx "core stop now" >/dev/null 2>&1 || true; sleep 2; }
    service asterisk start >/dev/null 2>&1 || asterisk -U asterisk -G asterisk
  fi
  for _ in $(seq 1 30); do asterisk_up && break; sleep 1; done
  asterisk_up || fail "Asterisk does not start. Look at: sudo tail -50 /var/log/asterisk/messages"
  asterisk -rx "core waitfullybooted" >/dev/null 2>&1 || true
}

# ---------- 2. backup ----------
say "2/6 Backing up the Asterisk config"
if [ -d "$ETC" ]; then cp -a "$ETC" "$ETC.backup-$STAMP"; echo "Saved to $ETC.backup-$STAMP"; else echo "Nothing to back up"; fi

# ---------- 3. Asterisk basics ----------
say "3/6 Checking Asterisk"
if [ ! -f "$ETC/asterisk.conf" ] || [ ! -f "$ETC/pjsip.conf" ] || [ ! -f "$ETC/extensions.conf" ]; then
  echo "Some standard config files are missing, restoring them"
  apt-get install -y -qq --reinstall -o Dpkg::Options::="--force-confmiss" asterisk-config >/dev/null \
    || fail "Could not restore Asterisk's config files."
fi
[ -f "$ETC/asterisk.conf" ] || fail "$ETC/asterisk.conf is still missing. Was Asterisk built from source? Then run 'make samples' in its source folder first."
id asterisk >/dev/null 2>&1 || fail "There is no 'asterisk' user. Was Asterisk built from source? Install it with apt instead."

RESTART=0
asterisk_up || RESTART=1
# A UDP transport defined in pjsip.conf (or a file it includes)?
if ! grep -rqsE '^\s*protocol\s*=\s*udp' "$ETC"/pjsip*.conf; then
  printf '\n; Added by the Phone Game installer: SIP over UDP on port 5060\n[phonegame-udp]\ntype=transport\nprotocol=udp\nbind=0.0.0.0:5060\n' >> "$ETC/pjsip.conf"
  echo "Added a SIP port (UDP 5060) to pjsip.conf"
  RESTART=1
fi
[ "$RESTART" = 1 ] && { echo "Starting Asterisk"; restart_asterisk; }
asterisk -rx "core waitfullybooted" >/dev/null 2>&1 || true
asterisk -rx "pjsip show transports" | grep -qi udp \
  || fail "Asterisk has no working SIP port. Is something else using UDP 5060? Check: sudo ss -lunp | grep 5060"
echo "OK"

# ---------- 4. the game ----------
say "4/6 Installing the game"
DATA=$(asterisk -rx "core show settings" | awk -F': *' '/Data directory/ {print $2; exit}' | tr -d '[:space:]')
DATA=${DATA:-/usr/share/asterisk}

PASSWORD=""
if [ ! -e "$ETC/phonegame-pjsip.conf" ] || [ "${NEW_PASSWORD:-}" = 1 ]; then
  PASSWORD=$( (tr -dc 'a-km-np-z2-9' </dev/urandom || true) | head -c 16)
  MD5=$(printf '%s' "6001:asterisk:$PASSWORD" | md5sum | cut -d' ' -f1)
  sed "s/@MD5_CRED@/$MD5/" asterisk/phonegame-pjsip.conf > "$ETC/phonegame-pjsip.conf"
fi
install -m 640 -o root -g asterisk asterisk/phonegame-extensions.conf "$ETC/phonegame-extensions.conf"
chown root:asterisk "$ETC/phonegame-pjsip.conf"; chmod 640 "$ETC/phonegame-pjsip.conf"
grep -q '^#include phonegame-pjsip.conf' "$ETC/pjsip.conf" || printf '\n#include phonegame-pjsip.conf\n' >> "$ETC/pjsip.conf"
grep -q '^#include phonegame-extensions.conf' "$ETC/extensions.conf" || printf '\n#include phonegame-extensions.conf\n' >> "$ETC/extensions.conf"

install -d -o asterisk -g asterisk "$DATA/sounds/custom"
install -m 644 -o asterisk -g asterisk sounds/*.wav "$DATA/sounds/custom/"

install -m 755 bin/phonegame-call /usr/local/bin/phonegame-call
[ -e /etc/phonegame.conf ] || install -m 644 phonegame.conf.example /etc/phonegame.conf
install -d -m 750 -o asterisk -g asterisk /var/spool/asterisk/phonegame-tmp
install -d -m 755 -o asterisk -g asterisk /var/lib/phonegame          # progress only, no secrets; the website checks it
install -d -o asterisk -g asterisk /var/spool/asterisk/outgoing

# The website (www-data) only drops a request file here; phonegame-web.path (or cron) then runs
# "phonegame-call web" as asterisk. So the website needs no sudo and no rights in Asterisk.
install -d -m 2770 -o asterisk -g www-data /var/lib/phonegame-web
chown asterisk:www-data /var/lib/phonegame-web; chmod 2770 /var/lib/phonegame-web
rm -f /etc/sudoers.d/phonegame                                       # used by older versions
# Backup: cron also checks once a minute (harmless if the systemd watcher already handled it).
install -d /etc/cron.d && install -m 644 systemd/phonegame-web.cron /etc/cron.d/phonegame
if [ "$HAS_SYSTEMD" = 1 ]; then
  install -m 644 systemd/phonegame-web.path systemd/phonegame-web.service /etc/systemd/system/
  systemctl daemon-reload
  systemctl enable -q --now phonegame-web.path
  systemctl restart phonegame-web.path
  systemctl is-active -q phonegame-web.path || fail "The website watcher did not start. Look at: sudo systemctl status phonegame-web.path"
else
  echo "No systemd: website requests are handled by cron once a minute"
fi

asterisk -rx "module reload res_pjsip.so" >/dev/null
asterisk -rx "dialplan reload" >/dev/null
asterisk -rx "pjsip show endpoint 6001" | grep -q 'Endpoint:  *6001' || fail "Phone line 6001 did not load. Look at: sudo tail -50 /var/log/asterisk/messages"
asterisk -rx "dialplan show 7000@phonegame-phone" | grep -q phonegame-call || fail "The game's dialplan did not load. Look at: sudo tail -50 /var/log/asterisk/messages"
echo "OK"

# ---------- 5. website ----------
say "5/6 Setting up the website"
install -d "$WEBROOT/phonegame"
install -m 644 web/phonegame/documentation.php "$WEBROOT/phonegame/documentation.php"
if [ -f site/index.html ]; then
  [ -f "$WEBROOT/index.html" ] && ! [ -e "$WEBROOT.backup-$STAMP" ] && cp -a "$WEBROOT" "$WEBROOT.backup-$STAMP"
  find site -mindepth 1 -maxdepth 1 ! -name README.md -exec cp -r {} "$WEBROOT/" \;
  echo "Copied your website from site/"
else
  echo "No website in site/ (the game works without it; see README.md to add yours)"
fi
install -m 644 web/phonegame-site.conf /etc/apache2/conf-available/phonegame-site.conf
a2enconf -q phonegame-site >/dev/null
a2enmod -q php* >/dev/null 2>&1 || true
start_service apache2
echo "OK"

# ---------- 6. firewall ----------
say "6/6 Firewall"
if command -v ufw >/dev/null && ufw status | grep -q "Status: active"; then
  ufw allow 5060/udp >/dev/null; ufw allow 10000:20000/udp >/dev/null; ufw allow 80/tcp >/dev/null
  echo "Opened 5060/udp, 10000-20000/udp and 80/tcp"
else
  echo "ufw is not on, nothing to do"
fi

IP=$(hostname -I 2>/dev/null | awk '{print $1}'); IP=${IP:-THIS-SERVER-IP}
say "Done! The Phone Game is installed."
if [ -n "$PASSWORD" ]; then
  cat <<DONE
Put this account into MicroSIP (or Zoiper / Linphone). Write the password down: it is not saved anywhere.

    SIP server : $IP
    Username   : 6001
    Password   : $PASSWORD
    Transport  : UDP
DONE
else
  echo "Phone line 6001 kept its password. For a new one: sudo NEW_PASSWORD=1 bash install.sh"
fi
case "$IP" in 10.0.2.*)
  cat <<WARN

NOTE: $IP is VirtualBox's internal (NAT) address, so phones and other PCs can't reach it.
Shut down the VM, set Settings > Network > Adapter 1 to "Bridged Adapter", start it again,
and use the address from 'hostname -I' instead (no reinstall needed).
WARN
esac
cat <<DONE

Website: http://$IP/
To play: when the phone app says Online, call 7000. The game hangs up and calls you back.
DONE
