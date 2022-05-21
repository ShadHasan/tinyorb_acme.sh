#!/bin/bash
############################################################################
# The entire code has written by Shad Hasan and it belongs to tinyorb.org
# Everyone are free to use this code in any form at its own discretion.
# It is hosted on: https://ShadHasan@bitbucket.org/tinyorb_team/tinyorb_dnsapi.git
#
# Description:
# This api allow to deploy and manage DNS on the given host.
#
#*************************** Warning ****************************************
# This script have broader access of the system. Use this script only from safe
# system else it can compromise the server.
#*************************** Warning ****************************************
##############################################################################
set -eE
# set -u  # enable for debugging, it will force to not use unbound variable
trap "Error occurred" ERR

path="$(readlink -f ${BASH_SOURCE[0]})"
path="$(dirname $(dirname $path))/resource/dnsapi_to"

# Here we source variable file
if [ -f $path/variable.sh ]; then
  source $path/variable.sh
else
  echo "Please create variable file at path: $path/variable.sh"
  exit 0
fi


zone_config_path=$path/tmpattempt/conf/$zone
meta_info=$zone_config_path/meta.info
if [ ! -d $zone_config_path ]; then
  echo "not exist, zone path creating"
  mkdir -p $zone_config_path
fi

if [ -f $meta_info ]; then
  source $meta_info
fi

function error_print() {
    echo "$@" 1>&2
    exit 0
}

function verify_dependency(){
  dependency_1=$(sshpass -V | head -n 1)
  if [[ "$dependency_1" =~ "sshpass" ]]; then
    echo "Dependency meet"
  else
    echo "Please install sshpass"
    exit 1
  fi
  if [[ "$1" == "m" ]]; then
    sshpass ssh -t $user@$master_dns_host -o StrictHostKeyChecking=no "echo 'connected'"
    echo "Connection verified"
  elif [ "$1" == "s" ]; then
    sshpass ssh -t $alt_user@$alt_dns_host -o StrictHostKeyChecking=no "echo 'connected'"
    echo "Connection verified"
  fi
}

function verify_just_deploy() {
  echo "Verifying just deployment"
  if [[ "$1" == "m" ]]; then
    result=$(sshpass ssh -t $user@$master_dns_host -o StrictHostKeyChecking=no "sudo docker image ls tinyorb/bind9 | grep latest" |  xargs echo)
  elif [[ "$1" == "s" ]]; then
    result=$(sshpass ssh -t $alt_user@$alt_dns_host -o StrictHostKeyChecking=no "sudo docker image ls tinyorb/bind9 | grep latest" |  xargs echo)
  else
    echo "No proper response"
    exit 1
  fi
  if [[ "$result" =~ "bind9" ]]; then
    echo "Verified dns image"
  else
    echo "Cannot find dns image, please use deploy command to deploy image"
    echo "Make sure you have appropriate permission to the user"
    exit 1
  fi
}

function verify_deploy() {
  verify_just_deploy $1
  echo "Verifying deployment"
  if [[ "$1" == "m" ]]; then
    result=$(sshpass ssh -t $user@$master_dns_host -o StrictHostKeyChecking=no "sudo docker ps -a | grep tinyorb_dns" |  xargs echo)
  elif [[ "$1" == "s" ]]; then
    result=$(sshpass ssh -t $alt_user@$alt_dns_host -o StrictHostKeyChecking=no "sudo docker ps -a | grep tinyorb_dns" |  xargs echo)
  else
    echo "No proper response"
    exit 1
  fi
  if [[ "$result" =~ "dns"  ]]; then
    echo "Verified dns service"
  else
    echo "Cannot find service, please use deploy command to create service"
    exit 1
  fi
}

function status() {
    echo "Verifying status"
    result="error"
    if [[ "$1" == "m" ]]; then
      result=$(sshpass ssh -t $user@$master_dns_host -o StrictHostKeyChecking=no "sudo docker ps -a | grep tinyorb_dns" | xargs echo )
    elif [[ "$1" == "s" ]]; then
      result=$(sshpass ssh -t $alt_user@$alt_dns_host -o StrictHostKeyChecking=no "sudo docker ps -a | grep tinyorb_dns" |  xargs echo)
    else
      echo "No proper response"
      exit 1
    fi
    if [[ "$result" =~ "Up" ]]; then
      echo "Service is running"
    elif [[ "$result" =~ "Created" ]]; then
      echo "Service found but not started"
    elif [[ "$result" =~ "Exited" ]]; then
      echo "Service is not running"
    else
      echo "Service status unknown"
      echo "Verify deployment status if you are troubleshooting"
    fi
}

function init_config() {
 echo "Warning! This will erase and reset the previous configuration and need to deploy again, if you want proceed please type 'yes' and enter?"
 read accept
 if [ "$accept" != "yes" ]; then
     exit 1;
 fi
 if [[ -z ${zone} ]]; then
      echo "zone domain cannot be emptied, Please declare 'zone' in variable file and source at the beginning"
 fi
 echo "By default ns1 is the name for master nameserver with ip $master_dns_host"
 nameserver="ns1"
 nameserver_ip=$master_dns_host
 if [[ "$enable_alt" == "true" ]]; then
  echo "By default ns2 is the name for alt nameserver with ip $alt_dns_host"
  alt_nameserver="ns2"
  alt_nameserver_ip=$alt_dns_host
  _y=""
 for i in 3 2 1; do _y=$_y$(echo $alt_nameserver_ip | cut -d "." -f $i).; done;
 alt_reverse_lookup=$_y"in-addr.arpa"
fi
 y=""
 for i in 3 2 1; do y=$y$(echo $nameserver_ip | cut -d "." -f $i).; done;
 reverse_lookup=$y"in-addr.arpa"
 echo "EMAIL without domain name, by default admin: "
 read mail
 if [[ "$mail" == "" ]]; then
    mail="admin"
 fi
 echo "TTL for SOA, if you want to use default value press enter: "
 read ttl
 if [[ "$ttl" == "" ]]; then
     ttl=443
 fi
 echo "Serial for SOA, if you want to use default value press enter: "
 read serial
 if [[ "$serial" == "" ]]; then
     serial=1
 fi
 echo "refresh value for SOA, if you want to use default value press enter: "
 read refresh
 if [[ "$refresh" == "" ]]; then
     refresh=43200
 fi
 echo "retry value for SOA, if you want to use default value press enter: "
 read retry
 if [[ "$retry" == "" ]]; then
      retry=600
  fi
 echo "expire value for SOA, if you want to use default value press enter: "
 read expire
 if [[ "$expire" == "" ]]; then
      expire=1209600
  fi
 echo "Cache TTL value for SOA, if you want to use default value press enter: "
 read cache_ttl
 if [[ "$cache_ttl" == "" ]]; then
      cache_ttl=600
  fi
 if [ -d $zone_config_path/master ]; then
   echo "deleting previous config"
   rm -rf $zone_config_path/master
 fi
 if [ -d $zone_config_path/alt ]; then
   echo "deleting previous config"
   rm -rf $zone_config_path/alt
 fi
 if [ -f $meta_info ]; then
  echo "deleting previous meta"
  rm -f $meta_info
fi
 touch $meta_info
 mkdir $zone_config_path/master
 mkdir $zone_config_path/alt

echo "Creating all necessary configuration"
cat > $meta_info << END
zone=$zone
nameserver=$nameserver
nameserver_ip=$nameserver_ip
reverse_lookup=$reverse_lookup
mail=$mail
ttl=$ttl
serial=$serial
refresh=$refresh
retry=$retry
expire=$expire
cache_ttl=$cache_ttl
END

if [[ "$enable_alt" == "true" ]]; then
  echo "alt_nameserver=$alt_nameserver" >> $meta_info
  echo "alt_nameserver_ip=$alt_nameserver_ip" >> $meta_info

  cat > $zone_config_path/master/forward.$zone.db << END
\$TTL    $ttl
@       IN      SOA     $nameserver.$zone. $mail.$zone. (
                        $serial        ; Serial
                        $refresh       ; Refresh
                        $retry         ; Retry
                        $expire        ; Expire
                        $cache_ttl )   ; Negative Cache TTL

;Name Server Information

    IN      NS      $nameserver.$zone.
    IN      NS      $alt_nameserver.$zone.

;IP address of Name Server

$nameserver.$zone.     IN      A       $nameserver_ip
$alt_nameserver.$zone.     IN      A       $alt_nameserver_ip
END

  cat > $zone_config_path/master/reverse.$zone.db << END
\$TTL    $ttl
@       IN      SOA     $nameserver.$zone. $mail.$zone. (
                        $serial        ; Serial
                        $refresh       ; Refresh
                        $retry         ; Retry
                        $expire        ; Expire
                        $cache_ttl )   ; Negative Cache TTL

;Name Server Information

    IN      NS      $nameserver.$zone.

;IP address of Name Server
$nameserver.$zone.     IN      A       $nameserver_ip
$alt_nameserver.$zone.     IN      A       $alt_nameserver_ip

; PTR record
$nameserver_ip     IN     PTR       $nameserver.$zone
$alt_nameserver_ip     IN     PTR       $alt_nameserver.$zone
END

  cat > $zone_config_path/master/named.conf.$zone << END
zone "$zone" IN {

      type master;

     file "/etc/bind/forward.$zone.db";

     allow-transfer { $alt_dns_host; }; // whom can transfer to here
     allow-update { none; };
     also-notify { $alt_dns_host; };  // change
};

zone "$reverse_lookup" IN {

     type master;

     file "/etc/bind/reverse.$zone.db";

     allow-transfer { $alt_dns_host; }; // whom can transfer to here
     allow-update { none; };
     also-notify { $alt_dns_host; }; // notify change
};
END

  cat > $zone_config_path/alt/named.conf.$zone << END
zone "$zone" IN {

     type slave;

     file "/var/cache/bind/forward.$zone.db";

     masters { $master_dns_host; };
};

zone "$alt_reverse_lookup" IN {

     type slave;

     file "/var/cache/bind/reverse.$zone.db";

     masters { $master_dns_host; };
};
END

  cat > $zone_config_path/alt/named.conf.options << END
acl "trusted" {
  $master_dns_host;
  $alt_dns_host;
  172.17.0.2;
  127.0.0.1;
  8.8.8.8;
  8.8.4.4;
};
options {
        directory "/var/cache/bind";
        recursion yes;
        auth-nxdomain no;
        allow-recursion { trusted; };
        listen-on-v6 { none; };
        listen-on { any; };
};
END

  cat > $zone_config_path/alt/named.conf << END
logging {
   channel "misc" {
      file "/var/log/bind_misc.log" versions 4 size 4m;
      print-time YES;
      print-severity YES;
      print-category YES;
   };
   channel "query" {
      file "/var/log/bind_query.log" versions 4 size 4m;
      print-time YES;
      print-severity YES;
      print-category YES;
   };
   category default {
      "misc";
   };
   category queries {
      "query";
   };
};
include "/etc/bind/named.conf.options";
include "/etc/bind/named.conf.$zone";
END

else

  cat > $zone_config_path/master/named.conf.$zone << END
zone "$zone" IN {

      type master;

     file "/etc/bind/forward.$zone.db";

     allow-update { none; };
};

zone "$reverse_lookup" IN {

     type master;

     file "/etc/bind/reverse.$zone.db";

     allow-update { none; };
};
END

  cat > $zone_config_path/master/named.conf << END
include "/etc/bind/named.conf.options";
include "/etc/bind/named.conf.$zone";
END

fi

  cat > $zone_config_path/master/named.conf.options << END
acl "trusted" {
  $master_dns_host;
  $alt_dns_host;
  172.17.0.2;
  127.0.0.1;
  8.8.8.8;
  8.8.4.4;
};
options {
        recursion yes;
        allow-recursion { any; }; // do not practice on dns server hosting zone. It Allow recursive query machine. Needed for forwarder.
        auth-nxdomain no;
        directory "/var/cache/bind";
        listen-on-v6 { none; };
        listen-on { any; };
        allow-transfer { none; };
        forwarders {
          8.8.8.8;
          8.8.4.4;
        };
        // forward only;  // uncomment when don't want local zones resolve. Every query will forwarded.
        // dnssec-enable yes;  // probably needed for public dns forward, not sure
        dnssec-validation no; // allow dnssec validation by default it is auto
        allow-query { any; };
        //allow-query-on { any; }; // this restrict from interface it accept the query in dns server
        allow-query-cache { any; }; // bind 9.* higher version have separated for cache query. Allow which what query can be cached.

};
END

  cat > $zone_config_path/master/named.conf << END
logging {
   channel "misc" {
      file "/var/log/bind_misc.log" versions 4 size 4m;
      print-time YES;
      print-severity YES;
      print-category YES;
   };
   channel "query" {
      file "/var/log/bind_query.log" versions 4 size 4m;
      print-time YES;
      print-severity YES;
      print-category YES;
   };
   category default {
      "misc";
   };
   category queries {
      "query";
   };
};
include "/etc/bind/named.conf.options";
include "/etc/bind/named.conf.$zone";
include "/etc/bind/named.conf.default-zones"; // root hint causing forwarder problem.
END

}

function push_config() {
  echo "pushing config"
  if [[ "$1" == "m" ]]; then
    sshpass scp -r $zone_config_path/master $user@$master_dns_host:$remote_tmp_path
    sshpass ssh -t $user@$master_dns_host -o StrictHostKeyChecking=no "rm -rf $remote_tmp_path'bind9' || true"
    sshpass ssh -t $user@$master_dns_host -o StrictHostKeyChecking=no "mv $remote_tmp_path'master' $remote_tmp_path'bind9'"
    sshpass ssh -t $user@$master_dns_host -o StrictHostKeyChecking=no "sudo docker cp  $remote_tmp_path'bind9' tinyorb_dns:/tmp/"
  elif [[ "$1" == "s" ]]; then
    sshpass scp -r $zone_config_path/alt $alt_user@$alt_dns_host:$remote_tmp_path
    sshpass ssh -t $alt_user@$alt_dns_host -o StrictHostKeyChecking=no "rm -rf $remote_tmp_path'bind9' || true"
    sshpass ssh -t $alt_user@$alt_dns_host -o StrictHostKeyChecking=no "mv $remote_tmp_path'alt' $remote_tmp_path'bind9'"
    sshpass ssh -t $alt_user@$alt_dns_host -o StrictHostKeyChecking=no "sudo docker cp  $remote_tmp_path'bind9' tinyorb_dns:/tmp/"
  else
    echo "No proper response"
    exit 1
  fi

}

function increment_forward_serial() {
  num=$(grep -nE "[ ]+[0-9]+[ ]+;[ ]+Serial" $zone_config_path/master/forward.$zone.db | grep -o -E "[0-9]+")
  line_no=$(echo $num | cut -d " " -f 1)
  serial_no=$(echo $num | cut -d " " -f 2)
  serial_no=$(expr $serial_no + 1)
  sed -r -i "s/([0-9])+.*Serial/$serial_no        ;     Serial/g" $zone_config_path/master/forward.$zone.db
}

function just_deploy() {
    if [[ "$1" == "m" ]]; then
        echo "deploying master dns"
        sshpass ssh -t $user@$master_dns_host -o StrictHostKeyChecking=no "sudo docker pull tinyorb/bind9"
    elif [[ "$1" == "s" ]]; then
      echo "deploying alt dns"
      sshpass ssh -t $alt_user@$alt_dns_host -o StrictHostKeyChecking=no "sudo docker pull tinyorb/bind9"
    else
      echo "No proper response"
      exit 1
    fi
}

function deploy() {
    dns_type=$1
    just_deploy $dns_type
    if [[ "$dns_type" == "m" ]]; then
      sshpass ssh -t $user@$master_dns_host -o StrictHostKeyChecking=no "sudo docker create --name=tinyorb_dns -p 53:53/tcp -p 53:53/udp --cap-add=NET_ADMIN tinyorb/bind9 | true"
      sshpass ssh -t $user@$master_dns_host -o StrictHostKeyChecking=no "touch $remote_tmp_path'bind_query.log' $remote_tmp_path'bind_misc.log'"
      sshpass ssh -t $user@$master_dns_host -o StrictHostKeyChecking=no "chmod 777 $remote_tmp_path'bind_query.log' $remote_tmp_path'bind_misc.log'"
      sshpass ssh -t $user@$master_dns_host -o StrictHostKeyChecking=no "sudo docker cp  $remote_tmp_path'bind_query.log' tinyorb_dns:/var/log/"
      sshpass ssh -t $user@$master_dns_host -o StrictHostKeyChecking=no "sudo docker cp  $remote_tmp_path'bind_misc.log' tinyorb_dns:/var/log/"
    elif [[ "$dns_type" == "s" ]]; then
      sshpass ssh -t $alt_user@$alt_dns_host -o StrictHostKeyChecking=no "sudo docker create --name=tinyorb_dns -p 53:53/tcp -p 53:53/udp --cap-add=NET_ADMIN tinyorb/bind9 | true"
      sshpass ssh -t $alt_user@$alt_dns_host -o StrictHostKeyChecking=no "rm $remote_tmp_path'bind_query.log' $remote_tmp_path'bind_misc.log' $remote_tmp_path'forward.'$zone'.db' $remote_tmp_path'reverse.'$zone'.db'"
      sshpass ssh -t $alt_user@$alt_dns_host -o StrictHostKeyChecking=no "touch $remote_tmp_path'bind_query.log' $remote_tmp_path'bind_misc.log' $remote_tmp_path'forward.'$zone'.db' $remote_tmp_path'reverse.'$zone'.db'"
      sshpass ssh -t $alt_user@$alt_dns_host -o StrictHostKeyChecking=no "chmod 777 $remote_tmp_path'bind_query.log' $remote_tmp_path'bind_misc.log' $remote_tmp_path'forward.'$zone'.db' $remote_tmp_path'reverse.'$zone'.db'"
      sshpass ssh -t $alt_user@$alt_dns_host -o StrictHostKeyChecking=no "sudo docker cp  $remote_tmp_path'bind_query.log' tinyorb_dns:/var/log/"
      sshpass ssh -t $alt_user@$alt_dns_host -o StrictHostKeyChecking=no "sudo docker cp  $remote_tmp_path'bind_misc.log' tinyorb_dns:/var/log/"
      sshpass ssh -t $alt_user@$alt_dns_host -o StrictHostKeyChecking=no "sudo docker cp  $remote_tmp_path'forward.'$zone'.db' tinyorb_dns:/var/cache/bind/forward.$zone.db"
      sshpass ssh -t $alt_user@$alt_dns_host -o StrictHostKeyChecking=no "sudo docker cp  $remote_tmp_path'reverse.'$zone'.db' tinyorb_dns:/var/cache/bind/reverse.$zone.db"
    else
      echo "No proper response"
      exit 1
    fi
    push_config $dns_type
}

function start_dns() {
  if [[ "$1" == "m" ]]; then
    echo "starting master dns"
    sshpass ssh -t $user@$master_dns_host -o StrictHostKeyChecking=no "sudo docker start tinyorb_dns"
  elif [[ "$1" == "s" ]]; then
    echo "starting alt dns"
    sshpass ssh -t $alt_user@$alt_dns_host -o StrictHostKeyChecking=no "sudo docker start tinyorb_dns"
  else
    echo "No proper response"
    exit 1
  fi
}

function stop_dns() {
  if [[ "$1" == "m" ]]; then
    echo "stopping master dns"
    sshpass ssh -t $user@$master_dns_host -o StrictHostKeyChecking=no "sudo docker stop tinyorb_dns"
  elif [[ "$1" == "s" ]]; then
    echo "stopping alt dns"
    sshpass ssh -t $alt_user@$alt_dns_host -o StrictHostKeyChecking=no "sudo docker stop tinyorb_dns"
  else
    echo "No proper response"
    exit 1
  fi
}

function undeploy() {
  if [[ "$1" == "m" ]]; then
    echo "going to undeploy master dns"
    sshpass ssh -t $user@$master_dns_host -o StrictHostKeyChecking=no "sudo docker kill tinyorb_dns || true"
    sshpass ssh -t $user@$master_dns_host -o StrictHostKeyChecking=no "sudo docker rm tinyorb_dns"
  elif [[ "$1" == "s" ]]; then
    echo "going to undeploy alt dns"
    sshpass ssh -t $alt_user@$alt_dns_host -o StrictHostKeyChecking=no "sudo docker kill tinyorb_dns || true"
    sshpass ssh -t $alt_user@$alt_dns_host -o StrictHostKeyChecking=no "sudo docker rm tinyorb_dns"
  else
    echo "No proper response"
    exit 1
  fi
}

function reload_dns() {
  push_config $1
  if [[ "$1" == "m" ]]; then
    echo "starting master dns"
    sshpass ssh -t $user@$master_dns_host -o StrictHostKeyChecking=no "sudo docker restart tinyorb_dns"
  elif [[ "$1" == "s" ]]; then
    echo "starting alt dns"
    sshpass ssh -t $alt_user@$alt_dns_host -o StrictHostKeyChecking=no "sudo docker restart tinyorb_dns"
  else
    echo "No proper response"
    exit 1
  fi
}

function verify_zone_config() {
  if [ -f $meta_info ]; then
    echo "Found config"
  else
    echo "Zone config not found. To create config use: ./dnsapi init"
    exit 1
  fi
  source $meta_info
  if [[ "$1" == "m" ]]; then
    echo "Checking on master dns"
    result=$(sshpass ssh -t $user@$master_dns_host -o StrictHostKeyChecking=no "sudo docker exec -t tinyorb_dns named-checkzone $zone /etc/bind/forward.$zone.db" | xargs echo ) RCODE=$?
    printf "%s" ${result@Q}
    result=$(sshpass ssh -t $user@$master_dns_host -o StrictHostKeyChecking=no "sudo docker exec -t tinyorb_dns named-checkzone $zone /etc/bind/reverse.$zone.db" | xargs echo ) RCODE=$?
    printf "%s" ${result@Q}
  elif [[ "$1" == "s" ]]; then
    echo "Checking on alt dns"
    result=$(sshpass ssh -t $alt_user@$alt_dns_host -o StrictHostKeyChecking=no "sudo docker exec -t tinyorb_dns named-checkzone $zone /etc/bind/forward.$zone.db" | xargs echo ) RCODE=$?
    printf "%s" ${result@Q}
    result=$(sshpass ssh -t $alt_user@$alt_dns_host -o StrictHostKeyChecking=no "sudo docker exec -t tinyorb_dns named-checkzone $zone /etc/bind/reverse.$zone.db" | xargs echo ) RCODE=$?
    printf "%s" ${result@Q}
  else
    echo "No proper response"
    exit 1
  fi
}

function verify_dns_config() {
  if [[ "$1" == "m" ]]; then
    echo "Checking on master dns"
    result=$(sshpass ssh -t $user@$master_dns_host -o StrictHostKeyChecking=no "sudo docker exec -t tinyorb_dns named-checkconf -p" | xargs echo ) RCODE=$?
  elif [[ "$1" == "s" ]]; then
    echo "Checking on alt dns"
    result=$(sshpass ssh -t $alt_user@$alt_dns_host -o StrictHostKeyChecking=no "sudo docker exec -t tinyorb_dns named-checkconf -p" | xargs echo ) RCODE=$?
  else
    echo "No proper response"
    exit 1
  fi
   printf "%s" ${result@Q}
}

function show_record(){
  readarray -t _record < <( grep -n ".*[ \t]$1[ \t].*" $zone_config_path/master/forward.$zone.db || echo "")
  for record in "${_record[@]}"; do
    result=$(echo $record | cut -d ":" -f 2)
    echo $result
  done
}

function remove_record(){
  readarray -t _record < <( grep -n "[ \t]$1[ \t]" $zone_config_path/master/forward.$zone.db || echo ""  )
  if [[ "${_record}" == "" ]]; then
    echo "No record of $1 found"
    exit 1
  fi
  i=1
  mrs="" #map record sequence
  for record in "${_record[@]}"; do
    result=$(echo $record | cut -d ":" -f 2)
    ln=$(echo $record | cut -d ":" -f 1)
    if [ $i -ne 1 ]; then
      mrs=$mrs";"
    fi
    mrs=$mrs$ln
    echo $i"    "$result
    i=$(expr $i + 1)
  done
  echo "Enter the record no. which you want to delete"
  read rl
  dl=$(echo $mrs | cut -d ";" -f $rl)
  echo "$dl and $mrs and $rl"
  if [[ "$dl" != "" ]] && [ $dl -gt 0 ]; then
    echo "Do you want to remove below record, enter 'y'"
    sed "$dl!d" $zone_config_path/master/forward.$zone.db    # '!' in sed act as compliment. Here 'd' return file by deleting line but '!d' return deleted line
    read confirm
      if [[ "$confirm" == "y" ]]; then
        echo $dl ## here you have to add delete line command by line number
        sed -i "${dl}d" $zone_config_path/master/forward.$zone.db
        echo "deleted line no $dl"
      fi
  else
    echo "Invalid input, don't find any such record"
    exit 1
  fi
}

function remove_record_by_name(){
  record=$1.$zone
  record_type=$2
  not_exist_not_ok $record $record_type
  re=$(echo "^$record.*[ \t]$record_type[ \t]")
  _record=$(grep -n "$re" $zone_config_path/master/forward.$zone.db)
  dl=$(echo $_record | cut -d ":" -f 1)
  sed -i "${dl}d" $zone_config_path/master/forward.$zone.db
  echo "deleted line no $dl"
}

function exist_not_ok(){
  record=$1
  record_type=$2
  file_path=$zone_config_path/master/forward.$zone.db
  re=".*$record.*[ \t]$record_type[ \t].*"
  exist=$(cat $file_path | grep "$re" | xargs echo )
  if [[ "$exist" != "" ]]; then
    echo "Already exist"
    exit 1
  fi
}

function not_exist_not_ok(){
  record=$1
  record_type=$2
  file_path=$zone_config_path/master/forward.$zone.db
  re="^$record.*[ \t]$record_type[ \t].*"
  exist=$(cat $file_path | grep "$re" | xargs echo )
  if [[ "$exist" == "" ]]; then
    echo "Not exist"
    exit 1
  fi
}

function validate_name(){
  if [[ "$1" =~ ^[a-zA-Z0-9]{1,63}(\.[a-zA-Z0-9]{1,63})*$ ]]; then
    echo "name ok"
  else
    echo "invalid name"
    exit 1
  fi
}

function validate_ip(){
  if [[ "$1" =~  (25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)(\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)){3}  ]]; then
    echo "ip ok"
  else
    echo "not valid ip"
    exit 1
  fi
}

function add_record_a(){
  printf "\n%s.%s.     IN      A       %s" $1 $zone $2 >> $zone_config_path/master/forward.$zone.db
  echo "Record '$1.$zone.     IN      A       $2' has been added to local config"
}

function add_record_txt(){
  printf "\n%s.%s.     IN      TXT       \"%s\"" $1 $zone $2 >> $zone_config_path/master/forward.$zone.db
  echo "Record $1.$zone.     IN      TXT       $2 has been added to local config"
}

function add_record_cname(){
  name=$1               # name should prefix without zone
  cname=$2              # cname should fqdn(fully qualified domain name)
  printf "\n%s.%s.     IN      CNAME       %s" $name $zone $cname >> $zone_config_path/master/forward.$zone.db
  echo "Record $name.$zone.     IN      CNAME       $cname has been added to local config"
}

function add_record_ns(){
  fqdn=$1.$zone # Use `@` if authoritative_domain is itself nameserver,
                          # Example: `@   NS     <fqdn_nameserver>`
                          # else on other resolver/provider like goddady/crazydomain use fqdn of domain
                          # Example: `sample.   NS    <fqdn_nameserver>`
  ip=$2

  printf "\n     IN       NS       %s" $fqdn >> $zone_config_path/master/forward.$zone.db
  echo 'Record    NS       $fqdn_nameserver has been added to local config'

  add_record_a $1 $ip
  add_record_ptr $ip $1
}

function add_record_ptr() {
  printf "\n%s     IN      PTR       %s.%s." $1 $2 $zone >> $zone_config_path/master/reverse.$zone.db
  echo "Record '$1     IN      A       $2.$zone.' has been added to local config"
}

function install_dnsclient() {
  if [[ "$native_dns_client" == "false" ]]; then
    echo "Enable native client to use"
    exit 1
  fi
  result=$(sudo docker ps -a | grep dnsclient | xargs echo)
  if [[ "$result" == "" ]]; then
    sudo docker pull tinyorb/dnsclient
    sudo docker create --name=dnsclient tinyorb/dnsclient | true
  fi
}

function set_client() {
  start_client
  echo "setting dns..."
  sudo docker exec dnsclient bash -c "echo m=$master_dns_host > /tmp/ns"
  if [[ "$enable_alt" == "true" ]]; then
    sudo docker exec dnsclient bash -c "echo a=$alt_dns_host >> /tmp/ns"
  fi
  stop_client
  start_client
}

function wait_client_up() {
  f=0
  for i in 1 2 3 4 5
  do
    sleep 1;
    y=$(sudo docker ps | grep dnsclient);
    if [[ "$y" =~ "Up" ]]; then
      echo "dnsclient is up"
      f=1
      break
    fi
  done
  if [[ "$f" == "0" ]]; then
    echo "Timeout! dnsclient status unknown"
  fi
}

function start_client() {
  install_dnsclient
  result=$(sudo docker ps | grep dnsclient | xargs echo)
  if ! [[ "$result" =~ "Up" ]]; then
    sudo docker start dnsclient
    wait_client_up
  else
    echo "dnsclient is already running"
  fi
}

function stop_client() {
  echo "dnsclient stopping..."
  sudo docker stop dnsclient | true
}

function status_client() {
  install_dnsclient
  result=$(sudo docker ps -a | grep dnsclient | xargs echo)
  echo $result
}

function record_verify_client() {
  name=$2
  case $1 in
    authority)
      command="dig $zone +noall +authority +norecurse"
      ;;
    NS)
      case $2 in
      master)
        server=$nameserver
        ;;
      alt)
        server=$nameserver2
        ;;
      *)
        echo "unknown nameserver"
        exit 1
        ;;
      esac
      command="dig $server.$zone +noall +answer +norecurse"
      ;;
    A)
      command="dig -t a $name.$zone +noall +answer +norecurse"
      ;;
    TXT)
      command="dig -t txt $name.$zone +noall +answer +norecurse"
      ;;
    CNAME)
      command="dig -t cname $name.$zone +noall +answer +norecurse"
      ;;
  esac
  echo "Executing $command"
  if [[ "$native_dns_client" == "true" ]]; then
    result=$(sudo docker exec dnsclient bash -c "$command")
  elif [[ "$native_dns_client" == "false" ]]; then
    result=$($command)
  fi
  if [[ "$3" == "" ]]; then
    if [[ "$result" == "" ]]; then
      error_print "No result $result"
    else
      echo "ok result: $result"
    fi
  else
    if [[ "$result" =~ "$3" ]]; then
      echo  "ok result $result"
    else
      error_print "No result $result"
    fi
  fi

}

function show_ns_client() {
    sudo docker exec dnsclient bash -c "cat /etc/resolv.conf"
}

call () {
  case $1 in
  init)
    init_config
    ;;
  start)
    case $2 in
    server)
      case $3 in
      master)
        start_dns "m"
        ;;
      alt)
        start_dns "s"
        ;;
      *)
        echo "Incorrect command, try 'dnsapi start server master|alt'"
        ;;
      esac
      ;;
    *)
      echo "Incorrect command, try 'dnsapi start server'"
    esac
    ;;
  stop)
    case $2 in
    server)
      case $3 in
      master)
        stop_dns "m"
        ;;
      alt)
        stop_dns "s"
        ;;
      *)
        echo "Incorrect command, try 'dnsapi stop server master|alt'"
        ;;
      esac
      ;;
    *)
      echo "Incorrect command, try 'dnsapi stop server'"
    esac
    ;;
  undeploy)
    case $2 in
    server)
      case $3 in
      master)
        stop_dns "m"
        undeploy "m"
        ;;
      alt)
        stop_dns "s"
        undeploy "s"
        ;;
      *)
        echo "Incorrect command, try 'dnsapi undeploy server master|alt'"
        ;;
      esac
      ;;
    *)
      echo "Incorrect command, try 'dnsapi undeploy server'"
    esac
    ;;
  reload)
    case $2 in
    server)
      case $3 in
      master)
        reload_dns "m"
        ;;
      alt)
        reload_dns "s"
        ;;
      *)
        echo "Incorrect command, try 'dnsapi reload server master|alt'"
        ;;
      esac
      ;;
    *)
      echo "Incorrect command, try 'dnsapi reload server'"
    esac
    ;;
  push)
    case $2 in
    server)
      case $3 in
      master)
        push_config "m"
        ;;
      alt)
        push_config "s"
        ;;
      *)
        echo "Incorrect command, try 'dnsapi push server master|alt'"
        ;;
      esac
      ;;
    *)
      echo "Incorrect command, try 'dnsapi push server'"
    esac
    ;;
  deploy)
    case $2 in
    server)
      case $3 in
      master)
        deploy "m"
        ;;
      alt)
        deploy "s"
        ;;
      *)
        echo "Incorrect command, try 'dnsapi deploy server master|alt'"
        ;;
      esac
      ;;
    *)
      echo "Incorrect command, try 'dnsapi deploy server'"
    esac
    ;;
  just_deploy)
    case $2 in
    server)
      case $3 in
      master)
        just_deploy "m"
        ;;
      alt)
        just_deploy "s"
        ;;
      *)
        echo "Incorrect command, try 'dnsapi just_deploy server master|alt'"
        ;;
      esac
      ;;
    *)
      echo "Incorrect command, try 'dnsapi just_deploy server'"
    esac
    ;;
  status)
    case $2 in
    server)
      case $3 in
      master)
        status "m"
        ;;
      alt)
        status "s"
        ;;
      *)
        echo "Incorrect input, try 'dnsapi status server master|alt'"
        ;;
      esac
      ;;
    *)
      echo "Incorrect input, try 'dnsapi status server'"
    esac
    ;;
  verify)
    case $2 in
    consistency)
      ;;
    connection|dependency)
      echo "Please make sure variable.sh path have relevant detail and sshpass install"
      case $3 in
      server)
        case $4 in
        master)
          verify_dependency "m"
          ;;
        alt)
          verify_dependency "s"
          ;;
        *)
          echo "Incorrect command, try 'dnsapi verify $2 server master|alt'"
          ;;
        esac
        ;;
      *)
        echo "Incorrect command, try 'dnsapi verify $2 server'"
      esac
      ;;
    zone)
      case $3 in
      server)
        case $4 in
        master)
          verify_zone_config "m"
          ;;
        alt)
          verify_zone_config "s"
          ;;
        *)
          echo "Incorrect command, try 'dnsapi verify $2 server master|alt'"
          ;;
        esac
        ;;
      *)
        echo "Incorrect command, try 'dnsapi verify $2 server'"
      esac
      ;;
    config)
      case $3 in
      server)
        case $4 in
        master)
          verify_dns_config "m"
          ;;
        alt)
          verify_dns_config "s"
          ;;
        *)
          echo "Incorrect command, try 'dnsapi verify $2 server master|alt'"
          ;;
        esac
        ;;
      *)
        echo "Incorrect command, try 'dnsapi verify $2 server'"
      esac
      ;;
    just_deploy)
      case $3 in
      server)
        case $4 in
        master)
          verify_just_deploy "m"
          ;;
        alt)
          verify_just_deploy "s"
          ;;
        *)
          echo "Incorrect command, try 'dnsapi verify $2 server master|alt'"
          ;;
        esac
        ;;
      *)
        echo "Incorrect command, try 'dnsapi verify $2 server'"
      esac
      ;;
    deploy)
      case $3 in
      server)
        case $4 in
        master)
          verify_deploy "m"
          ;;
        alt)
          verify_deploy "s"
          ;;
        *)
          echo "Incorrect command, try 'dnsapi verify $2 server master|alt'"
          ;;
        esac
        ;;
      *)
        echo "Incorrect command, try 'dnsapi verify $2 server'"
      esac
      ;;
    record)
      case $5 in
      expect)
        expectation=$6
        ;;
      *)
        expectation=""
      esac
      case $3 in
      txt|TXT)
        record_verify_client TXT $4 $expectation
        ;;
      a|A)
        record_verify_client A $4 $expectation
        ;;
      ns|NS)
        record_verify_client NS $4 $expectation
        ;;
      authority)
        record_verify_client authority
        ;;
      cname)
        record_verify_client cname $4 $expectation
        ;;
      help)
        echo "Usage:"
        echo "dnsapi verify record TXT|A|CNAME|NS|authority|help master|alt|<name>"
        ;;
      *)
        echo "   unknown input, Try"
        echo "   dnsapi verify record help"
        ;;
      esac
      ;;
    *)
      echo "Usage:"
      echo "dnsapi verify config|zone|deploy|just_deploy|record"
      ;;
    esac
    ;;
  show)
    case $2 in
    record)
      case $3 in
      A|a)
        show_record A
        ;;
      [tT][xX][tT])
        show_record TXT
        ;;
      [cC][nN][aA][mM][eE])
        show_record CNAME
        ;;
      [nN][sS])
        show_record NS
        ;;
      help)
        echo "Usage:"
        echo "dnsapi show record A|TXT|CNAME|NS|help"
        ;;
      *)
        echo "   unknown input, Try"
        echo "   dnsapi show record help"
        ;;
      esac
      ;;
    help)
      echo "Usage:"
      echo "dnsapi show record|zone|help"
      echo "Note: 'show' only present local config and cannot be synced with remote dns. To reload config use dnsapi reload."
      ;;
    *)
      echo "   unknown input, Try"
      echo "   dnsapi show help"
      ;;
    esac
    ;;
  -i)
    case $2 in
    add)
      case $3 in
      record)
        case $4 in
          [tT][xX][tT])
            echo "Enter name for TXT Record"
            read name
            validate_name $name
            exist_not_ok $name.$zone A
            echo "Enter value"
            read value
            add_record_txt $name $value
            change_success=0
            ;;
          [aA])
            echo "Enter name for A Record"
            read name
            validate_name $name
            exist_not_ok $name.$zone A
            echo "Enter ipv4 IP address"
            read ip
            validate_ip $ip
            add_record_a $name $ip
            change_success=0
            ;;
          [cC][nN][aA][mM][eE])
            echo "Enter name for CNAME Record"
            read name
            validate_name $name
            exist_not_ok $name.$zone A
            echo "Enter CNAME FQDN"
            read cname
            validate_name $cname
            add_record_cname $name $cname
            change_success=0
            ;;
          [nN][sS])
            echo "need to code"
            ;;
          help)
            echo "Usage:"
            echo "dnsapi add record a|txt|help"
            ;;
          *)
            echo "Not supported command"
            echo "   dnsapi add help"
            ;;
        esac
        ;;
      help)
        echo "Usage:"
        echo "dnsapi add record|help"
        ;;
      *)
        echo "Not supported command"
        echo "   dnsapi add help"
        ;;
      esac
      ;;
    remove)
      case $3 in
      record)
        case $4 in
        [aA])
          remove_record A
          change_success=0
          ;;
        [tT][xX][tT])
          remove_record TXT
          change_success=0
          ;;
        [cC][nN][aA][mM][eE])
          remove_record CNAME
          change_success=0
          ;;
        [nN][sS])
          remove_record NS
          change_success=0
          ;;
        help)
          echo "Usage:"
          echo "dnsapi remove record A|TXT|CNAME|NS|help"
          ;;
        *)
          echo "   Incorrect command, try below"
          echo "   dnsapi remove record help"
          ;;
        esac
        ;;
      help)
        echo "Usage:"
        echo "dnsapi remove record|help"
        ;;
      *)
        echo "   Incorrect input, try below"
        echo "  dnsapi remove help"
      esac
      ;;
    esac
    ;;
  client)
    case $2 in
    set)
      set_client
      ;;
    start)
      start_client
      ;;
    status)
      status_client
      ;;
    stop)
      stop_client
      ;;
    show)
      show_ns_client
      ;;
    *)
      echo "Incorrect command, try 'dnsapi client set|start|stop'"
    esac
    ;;
  add)
    case $2 in
    record)
      case $3 in
      [aA])
        case $4 in
        name)
          validate_name $5
          exist_not_ok $5.$zone A
          case $6 in
          ip)
            validate_ip $7
            add_record_a $5 $7
            change_success=0
            ;;
          *)
            echo "Incorrect command, dnsapi add record A name <name> ip <ip address>"
            ;;
          esac
          ;;
        help)
          echo "Incorrect command, dnsapi add record A name <name> ip <ip address>"
          ;;
        *)
          echo "Incorrct command, try 'dnsapi add record A name'"
        esac
        ;;
      [Cc][Nn][Aa][Mm][Ee])
        case $4 in
        name)
          validate_name $5
          exist_not_ok $5.$zone CNAME
          case $6 in
          cname)
            if [[ "$7" =~ ^[a-zA-Z0-9]{1,63}(\.[a-zA-Z0-9]{1,63})*$ ]]; then
              add_record_cname $5 $7
              change_success=0
            else
              echo "Provided FQDN CNAME is not valid"
              exit 1
            fi
            ;;
          *)
            echo "Incorrect command, dnsapi add record CNAME name <name> cname <fqdn>"
            ;;
          esac
          ;;
        help)
          echo "Incorrect command, dnsapi add record CNAME name <name> cname <fqdn>"
          ;;
        *)
          echo "Incorrect command, try 'dnsapi add record CNAME name'"
        esac
        ;;
      [Tt][Xx][Tt])
        case $4 in
        name)
          validate_name $5
          exist_not_ok $5.$zone TXT
          case $6 in
          val)
            if [[ "$7" != "" ]]; then
              add_record_txt $5 $7
              change_success=0
            else
              echo "expecting some value"
              exit 1
            fi
            ;;
          *)
            echo "Incorrect command, dnsapi add record TXT name <name> val <value>"
            ;;
          esac
          ;;
        help)
          echo "Incorrect command, dnsapi add record TXT name <name> val <value>"
          ;;
        *)
          echo "Incorrct command, try 'dnsapi add record TXT name <name> val <value>'"
        esac
        ;;
      [Nn][Ss])
        case $4 in
        name)
          validate_name $5
          case $6 in
          ip)
            validate_ip $7
            add_record_ns $5 $7
            change_success=0
            ;;
          *)
            echo "Incorrect command, try 'dnsapi add record NS nameserver name <name> ip <ip>'"
          esac
          ;;
        *)
          echo "Incorrect command, try 'dnsapi add record NS nameserver name <name> ip <ip>'"
        esac
        ;;
      help)
        echo "dnsapi add record A|CNAME|TXT|NS"
        ;;
      *)
        echo "Incorrect command, try 'dnsapi add record help"
        ;;
      esac
      ;;
    help)
      echo "dnsapi add record"
      ;;
    *)
      echo "Incorrect command, try 'dnsapi add help'"
      ;;
    esac
    ;;
  remove)
    case $2 in
      record)
        case $3 in
        [aA])
          case $4 in
          name)
            validate_name $5
            remove_record_by_name $5 A
            change_success=0
            ;;
          *)
            echo "Incorrect command, try 'dnsapi remove record A name <record name>'"
          esac
          ;;
        [Cc][Nn][Aa][Mm][Ee])
          case $4 in
          name)
            validate_name $5
            remove_record_by_name $5 CNAME
            change_success=0
            ;;
          *)
            echo "Incorrect command, try 'dnsapi remove record A name <record name>'"
          esac
          ;;
        [Tt][Xx][Tt])
          case $4 in
          name)
            validate_name $5
            remove_record_by_name $5 TXT
            change_success=0
            ;;
          *)
            echo "Incorrect command, try 'dnsapi remove record TXT name <record name>'"
          esac
          ;;
        [Nn][Ss])
          echo "NS record can be removed interactively"
          ;;
        help)
          echo "dnsapi remove record A|CNAME|TXT|NS"
          ;;
        *)
          echo "Incorrect command, try 'dnsapi remove record help"
          ;;
        esac
        ;;
      help)
        echo "dnsapi remove record"
        ;;
      *)
        echo "Incorrect command, try 'dnsapi remove help'"
        ;;
      esac
      ;;
  backup)
    ;;
  help)
    echo "Usage:"
    echo "dnsapi start|reload|stop|add|show|help|just_deploy|deploy|undeploy|verify|push|backup"
    echo "or,"
    echo "   dnsapi -i add|remove"
    ;;
  *)
    echo "unknown input, Try"
    echo "   dnsapi help"
    ;;
  esac

  if [[ "$change_success" == "0" ]]; then
    increment_forward_serial;
  fi
}

wait_resolve_ok() {
  res=""
  count=5
  while [ "$res" != ""  ] && [ $dl -gt 0 ];
  do
    sleep 1m
    res=$(dig -t txt $1 +noall +answer +norecurse | grep $2)
    count=$(expr $count - 1)
  done
  exit 1
}

wait_resolve_nok() {
  res="junk"
  count=5
  while [ "$res" == ""  ] && [ $dl -gt 0 ];
  do
    sleep 1m
    res=$(dig -t txt $1 +noall +answer +norecurse)
    count=$(expr $count - 1)
  done
  exit 1
}

dns_to_add() {
  fulldomain="${1}"
  txtvalue="${2}"
  name=$(echo $fulldomain | cut -d "." -f 1)
  call add record txt name $name val $txtvalue
  call reload server master
  wait_resolve_ok $fulldomain $txtvalue
}

dns_to_rm() {
  fulldomain="${1}"
  name=$(echo $fulldomain | cut -d "." -f 1)
  call remove record txt name $name
  call reload server master
  wait_resolve_nok $fulldomain
}
