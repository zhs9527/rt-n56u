#!/bin/sh

#######################################################################
# (1) run process from superuser root (less security)
# (0) run process from unprivileged user "nobody" (more security)
SVC_ROOT=0

# process priority (0-normal, 19-lowest)
SVC_PRIORITY=3
#######################################################################

SVC_NAME="Aria2"
SVC_PATH="/usr/bin/aria2c"
DIR_LINK="/mnt/aria"

func_start()
{
	# Make sure already running
	if [ -n "`pidof aria2c`" ] ; then
		return 0
	fi

	echo -n "Starting $SVC_NAME:."

	if [ ! -d "${DIR_LINK}" ] ; then
		echo "[FAILED]"
		logger -t "$SVC_NAME" "Cannot start: unable to find target dir!"
		return 1
	fi

	DIR_CFG="${DIR_LINK}/config"
	DIR_DL1="`cd \"$DIR_LINK\"; dirname \"$(pwd -P)\"`/Downloads"
	[ ! -d "$DIR_DL1" ] && DIR_DL1="${DIR_LINK}/downloads"

	[ ! -d "$DIR_CFG" ] && mkdir -p "$DIR_CFG"

	FILE_CONF="$DIR_CFG/aria2.conf"
	FILE_LIST="$DIR_CFG/incomplete.lst"

	touch "$FILE_LIST"

	aria_pport=`nvram get aria_pport`
	aria_rport=`nvram get aria_rport`
	aria_user=`nvram get http_username`
	aria_pass=`nvram get http_passwd`

	[ -z "$aria_rport" ] && aria_rport="6800"
	[ -z "$aria_pport" ] && aria_pport="16888"

	if [ ! -f "$FILE_CONF" ] ; then
		[ ! -d "$DIR_DL1" ] && mkdir -p "$DIR_DL1"
		chmod -R 777 "$DIR_DL1"
		cat > "$FILE_CONF" <<EOF

### XML-RPC
rpc-listen-all=true
rpc-allow-origin-all=true
#rpc-secret=
#rpc-user=$aria_user
#rpc-passwd=$aria_pass

### Common
dir=$DIR_DL1
max-download-limit=0
max-overall-download-limit=0
disable-ipv6=false

### File
file-allocation=falloc
#file-allocation=none
no-file-allocation-limit=10M
allow-overwrite=false
auto-file-renaming=true
continue=true
remote-time=true

### Bittorent
bt-enable-lpd=true
#bt-lpd-interface=eth2.2
bt-max-peers=0
bt-max-open-files=100
bt-request-peer-speed-limit=10M
bt-stop-timeout=0
enable-dht=true
enable-dht6=true
enable-peer-exchange=true
seed-ratio=1.0
seed-time=0
max-upload-limit=0
max-overall-upload-limit=0
user-agent=Mozilla/5.0 (Macintosh; Intel Mac OS X 10_13_6) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/72.0.3602.2 Safari/537.36
peer-agent=qBittorrent v4.1.3
peer-id-prefix=-qB4130-
bt-save-metadata=true
bt-load-saved-metadata=true
bt-remove-unselected-file=true

### FTP/HTTP
ftp-pasv=true
ftp-type=binary
timeout=120
connect-timeout=60
split=16
max-concurrent-downloads=3
max-connection-per-server=16
min-split-size=4M
check-certificate=false
http-accept-gzip=true
reuse-uri=false
no-netrc=true

### Log
log=$DIR_CFG/aria2.log
log-level=notice

EOF
	fi

	# aria2 needed home dir
	export HOME="$DIR_CFG"

	svc_user=""

	if [ $SVC_ROOT -eq 0 ] ; then
		chmod 777 "${DIR_LINK}"
		chown -R nobody "$DIR_CFG"
		svc_user=" -c nobody"
	fi

	if [ "`nvram get http_proto`" != "0" ]; then
		chmod 644 /etc/storage/https/server.crt /etc/storage/https/server.key
		SSL_OPT="--rpc-secure=true --rpc-certificate=/etc/storage/https/server.crt --rpc-private-key=/etc/storage/https/server.key"
	else
		SSL_OPT=
	fi

	start-stop-daemon -S -N $SVC_PRIORITY$svc_user -x $SVC_PATH -- \
		-D --enable-rpc=true --conf-path="$FILE_CONF" --input-file="$FILE_LIST" --save-session="$FILE_LIST" \
		--rpc-listen-port="$aria_rport" --listen-port="$aria_pport" --dht-listen-port="$aria_pport" $SSL_OPT

	if [ $? -eq 0 ] ; then
		echo "[  OK  ]"
		logger -t "$SVC_NAME" "daemon is started"
	else
		echo "[FAILED]"
	fi
}

func_stop()
{
	# Make sure not running
	if [ -z "`pidof aria2c`" ] ; then
		return 0
	fi

	echo -n "Stopping $SVC_NAME:."

	# stop daemon
	killall -q aria2c

	# gracefully wait max 15 seconds while aria2c stopped
	i=0
	while [ -n "`pidof aria2c`" ] && [ $i -le 15 ] ; do
		echo -n "."
		i=$(( $i + 1 ))
		sleep 1
	done

	aria_pid=`pidof aria2c`
	if [ -n "$aria_pid" ] ; then
		# force kill (hungup?)
		kill -9 "$aria_pid"
		sleep 1
		echo "[KILLED]"
		logger -t "$SVC_NAME" "Cannot stop: Timeout reached! Force killed."
	else
		echo "[  OK  ]"
	fi
}

func_reload()
{
	aria_pid=`pidof aria2c`
	if [ -n "$aria_pid" ] ; then
		echo -n "Reload $SVC_NAME config:."
		kill -1 "$aria_pid"
		echo "[  OK  ]"
	else
		echo "Error: $SVC_NAME is not started!"
	fi
}

case "$1" in
start)
	func_start
	;;
stop)
	func_stop
	;;
reload)
	func_reload
	;;
restart)
	func_stop
	func_start
	;;
*)
	echo "Usage: $0 {start|stop|reload|restart}"
	exit 1
	;;
esac
