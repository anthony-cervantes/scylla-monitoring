#!/usr/bin/env bash

if [ -f  env.sh ]; then
    . env.sh
fi

CURRENT_VERSION="master"
if [ -f CURRENT_VERSION.sh ]; then
    CURRENT_VERSION=`cat CURRENT_VERSION.sh`
fi

. versions.sh
if [ "$1" = "-e" ]; then
    DEFAULT_VERSION=${DEFAULT_ENTERPRISE_VERSION[$BRANCH_VERSION]}
fi
if [ -z "$BRANCH_VERSION" ]; then
  BRANCH_VERSION=$CURRENT_VERSION
fi
if [ -z ${DEFAULT_VERSION[$CURRENT_VERSION]} ]; then
    BRANCH_VERSION=`echo $CURRENT_VERSION|cut -d'.' -f1,2`
fi
if [ -z "$MANAGER_VERSION" ];then
  MANAGER_VERSION=${MANAGER_DEFAULT_VERSION[$BRANCH_VERSION]}
fi

if [ "$1" = "--version" ]; then
    echo "Scylla-Monitoring Stack version: $CURRENT_VERSION"
    echo "Supported versions:" ${SUPPORTED_VERSIONS[$BRANCH_VERSION]}
    echo "Manager supported versions:" ${MANAGER_SUPPORTED_VERSIONS[$BRANCH_VERSION]}
    exit
fi

if [ "$CURRENT_VERSION" = "master" ]; then
    echo ""
    echo "*****************************************************"
    echo "* WARNING: You are using the unstable master branch *"
    echo "* Check the README.md file for the stable releases  *"
    echo "*****************************************************"
    echo ""
    echo "Make sure you run generate-dashboards.sh to generate your dashboards."
    echo 'For example to use Scylla 2021.1 run `./generate-dashboards.sh -F -v 2021.1`'
    echo ""
fi

if [ "`id -u`" -eq 0 ]; then
    echo "Running as root is not advised, please check the documentation on how to run as non-root user"
else
    GROUPID=`id -g`
    USER_PERMISSIONS="-u $UID:$GROUPID"
fi

group_args=()
is_podman="$(docker --help | grep -o podman)"
if [ ! -z "$is_podman" ]; then
    group_args+=(--userns=keep-id)
fi

function usage {
  __usage="Usage: $(basename $0) [-h] [--version] [-e] [-d Prometheus data-dir] [-L resolve the servers from the manger running on the given address] [-G path to grafana data-dir] [-s scylla-target-file] [-n node-target-file] [-l] [-v comma separated versions] [-j additional dashboard to load to Grafana, multiple params are supported] [-c grafana environment variable, multiple params are supported] [-b Prometheus command line options] [-g grafana port ] [ -p prometheus port ] [-a admin password] [-m alertmanager port] [ -M scylla-manager version ] [-D encapsulate docker param] [-r alert-manager-config] [-R prometheus-alert-file] [-N manager target file] [-A bind-to-ip-address] [-C alertmanager commands] [-Q Grafana anonymous role (Admin/Editor/Viewer)] [-S start with a system specific dashboard set] [-T additional-prometheus-targets] [--no-loki] [--auto-restart] [--no-renderer]

Options:
  -h print this help and exit
  --version print the current monitoring version and the supported versions and exit.
  -e
  -d path/to/Prometheus/data/dir - Set an external data directory for the Prometheus data
  -L ip                          - Resolve the servers from a Scylla Manager running on the given address.
  -G path/to/Grafana/data-dir    - Set an external data directory for the Grafana data.
  -s path/to/scylla-target-file  - Read Scylla's target from the given file.
  -n path/to/node-target-file    - Override scylla target file for node_exporter.
  -l                             - If Set use the local host network, especially useful when a container needs
                                   to access the local host.
  -v comma separated versions    - Specify one or more Scylla versions, check --version for the supported versions.
  -j additional dashboard        - List additional dashboards to load to Grafana, multiple params are supported.
  -c grafana_environment         - Grafana environment variable, multiple params are supported.
  -b Prometheus command          - Prometheus command line options.
  -g grafana port                - Override the default Grafana port.
  -p prometheus port             - Override the default Prometheus port.
  -a admin password              - Set Grafna's Admin password.
  -m alertmanager port           - Override the default Prometheus port.
  -M scylla-manager version      - Override the default Scylla Manager version to use.
  -D docker param                - Encapsulate docker param, the parameter will be used by all containers.
  -r alert-manager-config        - Override the default alert-manager configuration file.
  -R prometheus-alert-file       - Override the default Prometheus alerts configuration file.
  -N path/to/manager/target file - Set the location of the target file for Scylla Manager.
  -A bind-to-ip-address          - Bind to a specific interface.
  -C alertmanager commands       - Pass the command to the alertmanager.
  -Q Grafana anonymous role      - Set the Grafana anonymous role to one of Admin/Editor/Viewer.
  -S dashbards-list              - Override the default set of dashboards with the spcefied one.
  -T path/to/prometheus-targets  - Adds additional Prometheus target files.
  --no-loki                      - If set, do not run Loki and promtail.
  --auto-restart                 - If set, auto restarts the containers on failure.
  --no-renderer                  - If set, do not run the Grafana renderer container.
  --thanos-sc                    - If set, run thanos side car with the Prometheus server.

The script starts Scylla Monitoring stack.
"
  echo "$__usage"
}

if [ -z "$PROMETHEUS_RULES" ]; then
  PROMETHEUS_RULES="$PWD/prometheus/prom_rules/:/etc/prometheus/prom_rules/"
fi

if [ -z "$VERSIONS" ]; then
  VERSIONS=${DEFAULT_VERSION[$BRANCH_VERSION]}
fi

if [ -z "$SCYLLA_TARGET_FILES" ]; then
  SCYLLA_TARGET_FILES=($PWD/prometheus/scylla_servers.yml $PWD/scylla_servers.yml)
fi
if [ -z "$SCYLLA_MANGER_TARGET_FILES" ]; then
  SCYLLA_MANGER_TARGET_FILES=($PWD/prometheus/scylla_manager_servers.yml $PWD/scylla_manager_servers.yml $PWD/prometheus/scylla_manager_servers.example.yml)
fi
if [ -z "$GRAFANA_ADMIN_PASSWORD" ]; then
  GRAFANA_ADMIN_PASSWORD=""
fi

if [ -z "$ALERTMANAGER_PORT" ]; then
  ALERTMANAGER_PORT=""
fi

if [ -z "$DOCKER_PARAM" ]; then
  DOCKER_PARAM=""
fi
if [ -z "$DATA_DIR" ]; then
  DATA_DIR=""
fi
if [ -z "$DATA_DIR_CMD" ]; then
  DATA_DIR_CMD=""
fi
if [ -z "$CONSUL_ADDRESS" ]; then
  CONSUL_ADDRESS=""
fi
if [ -z "$PROMETHEUS_TARGETS" ]; then
  PROMETHEUS_TARGETS=""
fi
if [ -z "$BIND_ADDRESS" ]; then
  BIND_ADDRESS=""
fi
if [ -z "$BIND_ADDRESS_CONFIG" ]; then
  BIND_ADDRESS_CONFIG=""
fi
if [ -z "$GRAFNA_ANONYMOUS_ROLE" ]; then
  GRAFNA_ANONYMOUS_ROLE=""
fi
if [ -z "$SPECIFIC_SOLUTION" ]; then
  SPECIFIC_SOLUTION=""
fi
if [ -z "$LDAP_FILE" ]; then
  LDAP_FILE=""
fi
if [ -z "$RUN_RENDERER" ]; then
  RUN_RENDERER="-E"
fi
if [ -z "$RUN_LOKI" ]; then
  RUN_LOKI=1
fi
if [ -z "$RUN_THANOS_SC" ]; then
  RUN_THANOS_SC=0
fi
for arg; do
	shift
	case $arg in
        (--no-loki) RUN_LOKI=0
            ;;
        (--no-renderer) RUN_RENDERER=""
            ;;
        (--thanos-sc) RUN_THANOS_SC=1
            ;;
        (--auto-restart) DOCKER_PARAM="--restart=on-failure"
            ;;
        (*) set -- "$@" "$arg"
            ;;
    esac
done

while getopts ':hleEd:g:p:v:s:n:a:c:j:b:m:r:R:M:G:D:L:N:C:Q:A:P:S:T:' option; do
  case "$option" in
    h) usage
       exit
       ;;
    v) VERSIONS=$OPTARG
       ;;
    M) MANAGER_VERSION=$OPTARG
       ;;
    d) DATA_DIR=$OPTARG
       ;;
    G) EXTERNAL_VOLUME="-G $OPTARG"
       ;;
    A) BIND_ADDRESS="$OPTARG:"
       BIND_ADDRESS_CONFIG="-A $OPTARG"
       ;;
    r) ALERT_MANAGER_RULE_CONFIG="-r $OPTARG"
       ;;
    R) if [[ -d "$OPTARG" ]]; then
        PROMETHEUS_RULES=`readlink -m $OPTARG`":/etc/prometheus/prom_rules/"
       else
        PROMETHEUS_RULES=`readlink -m $OPTARG`":/etc/prometheus/prometheus.rules.yml"
       fi
       ;;
    g) GRAFANA_PORT="-g $OPTARG"
       ;;
    m) ALERTMANAGER_PORT="-p $OPTARG"
       ;;
    T) PROMETHEUS_TARGETS="$PROMETHEUS_TARGETS -T $OPTARG"
       ;;
    Q) GRAFNA_ANONYMOUS_ROLE="-Q $OPTARG"
       ;;
    p) PROMETHEUS_PORT=$OPTARG
       ;;
    s) SCYLLA_TARGET_FILES=("$OPTARG")
       ;;
    n) NODE_TARGET_FILE=$OPTARG
       ;;
    l) DOCKER_PARAM="$DOCKER_PARAM --net=host"
       ;;
    L) CONSUL_ADDRESS="-L $OPTARG"
       ;;
    P) LDAP_FILE="-P $OPTARG"
       ;;
    a) GRAFANA_ADMIN_PASSWORD="-a $OPTARG"
       ;;
    j) GRAFANA_DASHBOARD_ARRAY+=("$OPTARG")
       ;;
    c) GRAFANA_ENV_ARRAY+=("$OPTARG")
       ;;
    C) ALERTMANAGER_COMMANDS+=("$OPTARG")
       ;;
    D) DOCKER_PARAM="$DOCKER_PARAM $OPTARG"
       ;;
    b) PROMETHEUS_COMMAND_LINE_OPTIONS_ARRAY+=("$OPTARG")
       ;;
    N) SCYLLA_MANGER_TARGET_FILES=($OPTARG)
       ;;
    S) SPECIFIC_SOLUTION="-S $OPTARG"
       ;;
    E) RUN_RENDERER="-E"
       ;;
    :) printf "missing argument for -%s\n" "$OPTARG" >&2
       echo "$usage" >&2
       exit 1
       ;;
   \?) printf "illegal option: -%s\n" "$OPTARG" >&2
       echo "$usage" >&2
       exit 1
       ;;
  esac
done

if [ -z "$CONSUL_ADDRESS" ]; then
    for f in ${SCYLLA_TARGET_FILES[@]}; do
        if [ -f $f ]; then
            SCYLLA_TARGET_FILE=$f
            break
        fi
    done

    if [ -z $SCYLLA_TARGET_FILE ]; then
        echo "Scylla target file '${SCYLLA_TARGET_FILES}' does not exist, you can use prometheus/scylla_servers.example.yml as an example."
        exit 1
    fi

    if [ -z $NODE_TARGET_FILE ]; then
       NODE_TARGET_FILE=$SCYLLA_TARGET_FILE
    fi


    if [ ! -f $NODE_TARGET_FILE ]; then
        echo "Node target file '${NODE_TARGET_FILE}' does not exist"
        exit 1
    fi

    for f in ${SCYLLA_MANGER_TARGET_FILES[@]}; do
        if [ -f $f ]; then
            SCYLLA_MANGER_TARGET_FILE=$f
            break
        fi
    done
    if [ -z $SCYLLA_MANGER_TARGET_FILE ]; then
        echo "Scylla-Manager target file '${SCYLLA_MANGER_TARGET_FILES}' does not exist, you can use prometheus/scylla_manager_servers.example.yml as an example."
        exit 1
    fi

    SCYLLA_TARGET_FILE="-v "$(readlink -m $SCYLLA_TARGET_FILE)":/etc/scylla.d/prometheus/scylla_servers.yml:Z"
    SCYLLA_MANGER_TARGET_FILE="-v "$(readlink -m $SCYLLA_MANGER_TARGET_FILE)":/etc/scylla.d/prometheus/scylla_manager_servers.yml:Z"
    NODE_TARGET_FILE="-v "$(readlink -m $NODE_TARGET_FILE)":/etc/scylla.d/prometheus/node_exporter_servers.yml:Z"
else
    SCYLLA_TARGET_FILE=""
    SCYLLA_MANGER_TARGET_FILE=""
    NODE_TARGET_FILE=""
fi

if [ -z $DATA_DIR ]
then
    USER_PERMISSIONS=""
    echo "Warning: without an external Prometheus directory, Prometheus data will be deleted on shutdown, use the -d command line flag for data persistence."
else
    if [ -d $DATA_DIR ]; then
        echo "Loading prometheus data from $DATA_DIR"
    else
        echo "Creating data directory $DATA_DIR"
        mkdir -p $DATA_DIR
    fi
    DATA_DIR_CMD="-v "$(readlink -m $DATA_DIR)":/prometheus/data:Z"
fi

if [[ $DOCKER_PARAM = *"--net=host"* ]]; then
    if [ ! -z "$ALERTMANAGER_PORT" ] || [ ! -z "$GRAFANA_PORT" ] || [ ! -z $PROMETHEUS_PORT ]; then
        echo "Port mapping is not supported with host network, remove the -l flag from the command line"
        exit 1
    fi
    HOST_NETWORK=1
fi
ALERTMANAGER_COMMAND=""
for val in "${ALERTMANAGER_COMMANDS[@]}"; do
    ALERTMANAGER_COMMAND="$ALERTMANAGER_COMMAND -C $val"
done

echo "Wait for alert manager container to start"

AM_ADDRESS=`./start-alertmanager.sh $ALERTMANAGER_PORT -D "$DOCKER_PARAM" $ALERTMANAGER_COMMAND $BIND_ADDRESS_CONFIG $ALERT_MANAGER_RULE_CONFIG`
if [ $? -ne 0 ]; then
    echo "$AM_ADDRESS"
    exit 1
fi
echo "Wait for Loki container to start."
LOKI_ADDRESS="127.0.0.1"
if [ $RUN_LOKI -eq 1 ]; then
	LOKI_ADDRESS=`./start-loki.sh $BIND_ADDRESS_CONFIG -D "$DOCKER_PARAM" -m $AM_ADDRESS`
	if [ $? -ne 0 ]; then
	    echo "$LOKI_ADDRESS"
	    exit 1
	fi
fi

if [ -z $PROMETHEUS_PORT ]; then
    PROMETHEUS_PORT=9090
    PROMETHEUS_NAME=aprom
else
    PROMETHEUS_NAME=aprom-$PROMETHEUS_PORT
fi

docker container inspect $PROMETHEUS_NAME > /dev/null 2>&1
if [ $? -eq 0 ]; then
    printf "\nSome of the monitoring docker instances ($PROMETHEUS_NAME) exist. Make sure all containers are killed and removed. You can use kill-all.sh for that\n"
    exit 1
fi


# Exit if Docker engine is not running
if [ ! "$(docker ps)" ]
then
        echo "Error: Docker engine is not running"
        exit 1
fi

for val in "${PROMETHEUS_COMMAND_LINE_OPTIONS_ARRAY[@]}"; do
    PROMETHEUS_COMMAND_LINE_OPTIONS+=" -$val"
done

./prometheus-config.sh -m $AM_ADDRESS $CONSUL_ADDRESS $PROMETHEUS_TARGETS

if [ -z $HOST_NETWORK ]; then
    PORT_MAPPING="-p $BIND_ADDRESS$PROMETHEUS_PORT:9090"
fi

docker run -d $DOCKER_PARAM $USER_PERMISSIONS \
     $DATA_DIR_CMD \
     "${group_args[@]}" \
     -v $PWD/prometheus/build/prometheus.yml:/etc/prometheus/prometheus.yml:Z \
     -v $PROMETHEUS_RULES:z \
     $SCYLLA_TARGET_FILE \
     $SCYLLA_MANGER_TARGET_FILE \
     $NODE_TARGET_FILE \
     $PORT_MAPPING --name $PROMETHEUS_NAME prom/prometheus:$PROMETHEUS_VERSION  --web.enable-lifecycle --config.file=/etc/prometheus/prometheus.yml $PROMETHEUS_COMMAND_LINE_OPTIONS

if [ $? -ne 0 ]; then
    echo "Error: Prometheus container failed to start"
    echo "For more information use: docker logs $PROMETHEUS_NAME"
    exit 1
fi
if [ "$VERSIONS" = "latest" ]; then
	VERSIONS=$LATEST
else
	if [ "$VERSIONS" = "all" ]; then
		VERSIONS=$ALL
	fi
fi

# Number of retries waiting for a Docker container to start
RETRIES=7

# Wait till Prometheus is available
printf "Wait for Prometheus container to start."
TRIES=0
until $(curl --output /dev/null -f --silent http://localhost:$PROMETHEUS_PORT) || [ $TRIES -eq $RETRIES ]; do
    printf '.'
    ((TRIES=TRIES+1))
    sleep 5
done
echo

if [ ! "$(docker ps -q -f name=$PROMETHEUS_NAME)" ]
then
        echo "Error: Prometheus container failed to start"
        echo "For more information use: docker logs $PROMETHEUS_NAME"
        exit 1
fi

# Can't use localhost here, because the monitoring may be running remotely.
# Also note that the port to which we need to connect is 9090, regardless of which port we bind to at localhost.
DB_ADDRESS="$(docker inspect --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $PROMETHEUS_NAME):9090"

if [ ! -z "$is_podman" ] && [ "$DB_ADDRESS" = ":9090" ]; then
    HOST_IP=`hostname -I | awk '{print $1}'`
    DB_ADDRESS="$HOST_IP:9090"
fi

if [ $RUN_THANOS_SC -eq 1 ]; then
    if [ -z $DATA_DIR ]; then
        echo "You must use external prometheus directory to use the thanos side cart"
    else
        ./start-thanos-sc.sh -d $DATA_DIR -a $DB_ADDRESS
    fi
fi

for val in "${GRAFANA_ENV_ARRAY[@]}"; do
        GRAFANA_ENV_COMMAND="$GRAFANA_ENV_COMMAND -c $val"
done

for val in "${GRAFANA_DASHBOARD_ARRAY[@]}"; do
        GRAFANA_DASHBOARD_COMMAND="$GRAFANA_DASHBOARD_COMMAND -j $val"
done

./start-grafana.sh $LDAP_FILE -L $LOKI_ADDRESS $BIND_ADDRESS_CONFIG $RUN_RENDERER $SPECIFIC_SOLUTION -p $DB_ADDRESS $GRAFNA_ANONYMOUS_ROLE -D "$DOCKER_PARAM" $GRAFANA_PORT $EXTERNAL_VOLUME -m $AM_ADDRESS -M $MANAGER_VERSION -v $VERSIONS $GRAFANA_ENV_COMMAND $GRAFANA_DASHBOARD_COMMAND $GRAFANA_ADMIN_PASSWORD
