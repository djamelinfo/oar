#! /bin/sh

### BEGIN INIT INFO
# Provides:         oar-node
# Required-Start:   $network $local_fs $remote_fs
# Required-Stop:
# Default-Start:    2 3 4 5
# Default-Stop:     0 1 6
# Short-Description:    OAR node init script (launch its own sshd)
### END INIT INFO

# $Id$


PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
NAME=oar-node
DESC=oar-node
OAR_SSHD_CONF="/etc/oar/sshd_config"
SSHD_OPTS="-f $OAR_SSHD_CONF -o PidFile=/var/lib/oar/oar_sshd.pid"

start_oar_node() {
    echo " * Edit start_oar_node function in /etc/default/oar-node if you want"
    echo "   to perform a specific action (e.g. to switch the node to Alive)"
}

stop_oar_node() {
    echo " * Edit stop_oar_node function in /etc/default/oar-node if you want"
    echo "   to perform a specific action (e.g. to switch the node to Absent)"
}

# Include oar defaults if available
if [ -f /etc/default/oar-node ] ; then
    . /etc/default/oar-node
fi

set -e

case "$1" in
  start)
    echo "Starting $DESC:"
    if [ -f "$OAR_SSHD_CONF" ] ; then
        if start-stop-daemon --start -N "-20" --quiet --pidfile /var/lib/oar/oar_sshd.pid --exec /usr/sbin/sshd -- $SSHD_OPTS; then
            echo " * OAR dedicated SSH server started."
        else
            echo " * Failed to start OAR dedicated SSH server."
            exit 1
        fi
    fi
    start_oar_node
    ;;
  stop)
    echo "Stopping $DESC: "
    if [ -f "$OAR_SSHD_CONF" ] ; then
        if start-stop-daemon --stop --quiet --pidfile /var/lib/oar/oar_sshd.pid; then
            echo " * OAR dedicated SSH server stopped."
        else
            echo " * Failed to stop OAR dedicated SSH server."
        fi
    fi
    stop_oar_node
    ;;
  reload|force-reload|restart)
        $0 stop
        sleep 1
        $0 start
        ;;
  *)
    N=/etc/init.d/$NAME
    echo "Usage: $N {start|restart|stop}" >&2
    exit 1
    ;;
esac

exit 0