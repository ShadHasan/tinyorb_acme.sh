#!/bin/bash

## Sample for inner script can be call like below:
# sudo docker exec -it tinyorb_acme bash -c /root/.acme.sh/dnsapi/dns_to.sh init dns

case $1 in
argument=${@:2}
dns)
  sudo docker exec -it tinyorb_acme bash -c "/root/.acme.sh/dnsapi/dns_to.sh ${argument}"
  ;;
acme)
  sudo docker exec -it tinyorb_acme bash -c "/root/.acme.sh/acme.sh ${argument}"
  ;;
esac