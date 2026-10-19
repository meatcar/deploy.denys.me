# shellcheck shell=bash

export BAO_ADDR="${BAO_ADDR:-https://bao.vpn.denys.me}"
bao_host="${BAO_ADDR#*://}"
bao_host="${bao_host%%/*}"
bao_host="${bao_host%%:*}"
export NO_PROXY="${NO_PROXY:-${no_proxy:-}}"
case ",$NO_PROXY," in
*",$bao_host,"*) ;;
*) NO_PROXY="${NO_PROXY:+$NO_PROXY,}$bao_host" ;;
esac
export no_proxy="$NO_PROXY"
unset bao_host
