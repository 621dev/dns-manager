#!/bin/bash
# ============================================================
# 도커 환경용 zone_manager.sh
# 주요 변경사항:
#   - SCRIPT_DIR 기반 data/ 경로 사용 (dns_data.txt)
#   - 기능 자체는 원본과 동일
# ============================================================

source "$SCRIPT_DIR/zone_crud_docker.sh"

manage_zone(){
    local _input
    local -a _zonearr=()
    local _currentpage=0
    zone_list_reload _zonearr
    while :
    do
        sleep 2 && clear
        show_zone_list _zonearr ${_currentpage}
        echo "ZONE은 도메인과 IP 주소 간의 연결 정보를 담고 있는 파일입니다."
        echo "[. 다음 페이지    ]. 이전 페이지      :숫자. 해당 번호의 페이지로 이동"
        echo "-----------------------------------------------"
        echo "1. ZONE 조회 (미구현)"
        echo "2. ZONE 추가"
        echo "3. ZONE 수정"
        echo "4. ZONE 삭제"
        echo "q. 메인 메뉴 복귀"
        echo "==============================================="
        read -p "원하는 작업을 선택하세요 : " _input
        case "$_input" in
            1) echo "미구현 항목입니다." ;;
            2) select_add_zone; zone_list_reload _zonearr ;;
            3) select_update_zone _zonearr; zone_list_reload _zonearr ;;
            4) select_delete_zone _zonearr ;;
            "q") return 0 ;;
            *) echo "잘못된 입력입니다. 다시 시도해주세요." ;;
        esac
    done
}

select_add_zone() {
    local _input
    while :
    do
        echo "============================================"
        echo "1. 정방향 생성"
        echo "2. 역방향 생성"
        echo "q. 이전 메뉴 복귀"
        echo "============================================"
        read -p "원하는 작업을 선택하세요 : " _input
        case $_input in
            1) add_forward_zone ;;
            2) add_reverse_zone ;;
            "q") return 0 ;;
            *) echo "잘못된 입력입니다. 다시 시도해주세요." ;;
        esac
    done
}

select_delete_zone() {
    local -n _refzonearr=$1
    while :
    do
        sleep 2 && clear
        show_zone_list _refzonearr ${currentpage}
        echo "[. 다음 페이지    | ]. 이전 페이지    | :숫자. 해당 번호의 페이지로 이동"
        echo "1. 도메인을 입력하여 삭제 (정방향 삭제)"
        echo "2. 네트워크 주소를 입력하여 삭제 (역방향 HOST, 네트워크 삭제)"
        echo "q. 메인 메뉴 복귀"
        echo "==============================================="
        read -p "원하는 작업을 선택하세요 : " _input
        case "$_input" in
            1)
                read -p "도메인 : " _inputdomain
                if [ "$_inputdomain" == "0" ]; then continue; fi
                domain_delete_zone "$_inputdomain"
                zone_list_reload _refzonearr
                ;;
            2)
                read -p "네트워크 : " _inputnetwork
                if [ "$_inputnetwork" == "q" ]; then continue; fi
                echo "1. 네트워크 주소 삭제  2. 호스트 주소 삭제  q. 메뉴 복귀"
                read -p "원하는 작업을 선택하세요 : " _input
                case "$_input" in
                    1) network_delete_zone "$_inputnetwork"; zone_list_reload _refzonearr ;;
                    2) hostip_delete_zone "$_inputnetwork"; zone_list_reload _refzonearr ;;
                    "q") continue ;;
                    *) echo "잘못된 입력입니다." ;;
                esac
                ;;
            "q") return 0 ;;
            *) echo "잘못된 입력입니다. 다시 시도해주세요." ;;
        esac
    done
}

select_update_zone() {
    local -n _refzonearr=$1
    local _input
    local _service_arr=()
    local _ip_arr=()
    while :
    do
        sleep 2 && clear
        show_zone_list _refzonearr 0
        echo "1. 서비스 수정  2. 호스트 수정  q. 이전 메뉴 복귀"
        echo "==============================================="
        read -p "원하는 작업을 선택하세요 : " _input
        case "$_input" in
            1)
                read -p "수정할 도메인을 입력해주세요 (q. 취소) : " _domain
                if [ "$_domain" == "q" ] || [ "$_domain" == "Q" ]; then continue; fi
                if ! grep -E "^zone[[:space:]]+\"${_domain}\"[[:space:]]+IN" /etc/named.rfc1912.zones &>> "$LOG_FILE"; then
                    echo "${_domain} 도메인이 선언되어 있지 않습니다."
                    continue
                fi
                if [ ! -f "/var/named/${_domain}.zone" ]; then
                    echo "${_domain}.zone 파일이 존재하지 않습니다."
                    continue
                fi
                while :
                do
                    show_service_list ${_domain} _service_arr _ip_arr 0
                    echo "1. 서비스 추가  2. 서비스 삭제  q. 이전 메뉴 복귀"
                    read -p "원하는 작업을 선택하세요 : " _input
                    case "$_input" in
                        1)
                            while :
                            do
                                read -p "추가할 서비스의 IP (q. 취소) : " _ip
                                if [ "$_ip" == "q" ]; then break; fi
                                read -p "추가할 서비스 이름 (q. 취소) : " _service
                                if [ "$_service" == "q" ]; then break; fi
                                add_forward_service "$_domain" "$_service" "$_ip"
                            done
                            ;;
                        2)
                            while :
                            do
                                read -p "삭제할 서비스 이름 (q. 취소) : " _service
                                if [ "$_service" == "q" ]; then break; fi
                                delete_forward_service "$_domain" "$_service"
                            done
                            ;;
                        "q"|"Q") break ;;
                        *) echo "잘못된 입력입니다." ;;
                    esac
                done
                ;;
            2)
                read -p "네트워크 주소 입력 (예 : 192.168.10, q. 복귀) : " _inputnetwork
                if [ "$_inputnetwork" == "q" ]; then continue; fi
                _iparr=( $(split_dot "$_inputnetwork") )
                local _reverseip="${_iparr[2]}.${_iparr[1]}.${_iparr[0]}"
                if ! grep -E "^zone[[:space:]]+\"${_reverseip}\.in-addr\.arpa\"[[:space:]]+IN" /etc/named.rfc1912.zones &>> "$LOG_FILE"; then
                    echo "${_reverseip} 대역대는 선언되지 않았습니다."
                    continue
                fi
                if [ ! -f "/var/named/${_reverseip}.rev" ]; then
                    echo "${_reverseip}.rev 파일이 존재하지 않습니다."
                    continue
                fi
                while :
                do
                    echo "1. 호스트 추가  2. 호스트 삭제  q. 이전 메뉴 복귀"
                    read -p "원하는 작업을 선택하세요 : " _input
                    case "$_input" in
                        1)
                            while :
                            do
                                read -p "추가할 호스트 ip (q. 취소) : " _hostip
                                if [ "$_hostip" == "q" ]; then break; fi
                                read -p "추가할 도메인 (q. 취소) : " _domain
                                if [ "$_domain" == "q" ]; then break; fi
                                add_reverse_host "$_domain" "$_reverseip" "$_hostip"
                            done
                            ;;
                        2)
                            while :
                            do
                                read -p "삭제할 호스트 IP (q. 복귀) : " _hostip
                                if [ "$_hostip" == "q" ]; then break; fi
                                delete_reverse_host "$_reverseip" "$_hostip"
                            done
                            ;;
                        "q"|"Q") break ;;
                        *) echo "잘못된 입력입니다." ;;
                    esac
                done
                ;;
            "q"|"Q") return 0 ;;
            *) echo "잘못된 입력입니다." ;;
        esac
    done
}

check_ip() {
    local _inputip="$1"
    local -a _arrip
    _arrip=( $(split_dot "$_inputip") )

    if [ ${#_arrip[@]} -ne 4 ]; then
        echo "IP 주소는 4개의 옥텟으로 구성되어야 합니다."
        return 1
    fi

    if [[ "$_inputip" == "0.0.0.0" || "$_inputip" == "255.255.255.255" ]]; then
        echo "IP 주소는 0.0.0.0 또는 255.255.255.255 일 수 없습니다."
        return 1
    fi

    for _octet in "${_arrip[@]}"; do
        if [[ ! "$_octet" =~ ^[0-9]+$ ]]; then
            echo "IP 주소는 숫자와 점으로만 구성되어야 합니다."
            return 1
        elif (( _octet < 0 || _octet > 255 )); then
            echo "IP 주소의 각 옥텟은 0에서 255 사이여야 합니다."
            return 1
        elif [[ "$_octet" =~ ^0[0-9]+$ ]]; then
            echo "0으로 시작하는 두 자리 숫자는 가질 수 없습니다."
            return 1
        fi
    done
    return 0
}

split_dot() {
    local _input="$1"
    local -a _temp_arr
    IFS='.' read -r -a _temp_arr <<< "$_input"
    echo "${_temp_arr[@]}"
}

zone_list_reload() {
    local -n _refarr=$1
    local _filepath=${2:-/etc/named.rfc1912.zones}
    _refarr=()
    local -a _default_zones=(
        "localhost.localdomain"
        "localhost"
        "1.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.ip6.arpa"
        "1.0.0.127.in-addr.arpa"
        "0.in-addr.arpa"
    )
    local -a _allzones
    _allzones=($(awk -F'"' '/^zone "/ {print $2}' "$_filepath"))

    for _zone in "${_allzones[@]}"; do
        local _isdefault=false
        for _default_zone in "${_default_zones[@]}"; do
            if [[ "$_zone" == "$_default_zone" ]]; then
                _isdefault=true
                break
            fi
        done
        if ! $_isdefault; then
            _refarr+=("$_zone")
        fi
    done
}

show_zone_list(){
    local -n _szl_refzonearr=$1
    local _currentpage=${2:-0}
    local _maxzonecount=7
    local _zonetotal=${#_szl_refzonearr[@]}
    local _start=$(( _currentpage * _maxzonecount ))
    local _end=$(( _start + _maxzonecount ))
    local _totalpages=$(( _zonetotal == 0 ? 1 : (_zonetotal - 1) / _maxzonecount ))

    echo "==============================================="
    echo "ZONE LIST"
    echo "==============================================="
    for (( i = _start; i < _end && i < _zonetotal; i++ )); do
        echo "$((i+1)). ${_szl_refzonearr[i]}"
    done
    echo "==============================================="
    echo "PAGE : $((_currentpage+1)) / $((_totalpages+1)) | TOTAL ZONE COUNT : ${_zonetotal}"
    echo "==============================================="
}

reload_service_list(){
    local _rsl_filepath="/var/named/${1}.zone"
    local -n _rsl_ref_service_arr=$2
    local -n _rsl_ref_ip_arr=$3
    _rsl_ref_service_arr=()
    _rsl_ref_ip_arr=()
    _rsl_ref_service_arr=($(awk '/IN A/ {print $1}' "$_rsl_filepath"))
    _rsl_ref_ip_arr=($(awk '/IN A/ {print $4}' "$_rsl_filepath"))
}

show_service_list(){
    local _domain=$1
    local -n _ssl_ref_service_arr=$2
    local -n _ssl_ref_ip_arr=$3
    reload_service_list "$_domain" "$2" "$3"
    local _cur_page=${4:-0}
    local _max_service_cnt=7
    local _service_total=${#_ssl_ref_service_arr[@]}
    local _start=$(( _cur_page * _max_service_cnt ))
    local _end=$(( _start + _max_service_cnt ))
    local _totalpages=$(( _service_total == 0 ? 1 : (_service_total - 1) / _max_service_cnt ))

    echo "==============================================="
    for (( i = _start; i < _end && i < _service_total; i++ )); do
        echo "$((i+1)). ${_ssl_ref_service_arr[i]} (${_ssl_ref_ip_arr[i]})"
    done
    echo "PAGE : $((_cur_page+1)) / $((_totalpages+1)) | TOTAL SERVICE COUNT : ${_service_total}"
    echo "==============================================="
}

update_serial() {
    local _zonefile=$1
    local _serial=$(awk '/serial/ {print $1}' "$_zonefile")
    local _newserial=$((_serial + 1))
    sed -i "/serial/{s/${_serial}/${_newserial}/}" "$_zonefile"
}

update_decl_serial() {
    local _datepath=$1
    local _serial=$(awk -F':' '/ZONE_DECL_SERIAL/ {print $2}' "$_datepath")
    local _newserial=$((_serial + 1))
    sed -i "s/^ZONE_DECL_SERIAL:.*/ZONE_DECL_SERIAL:${_newserial}/" "$_datepath"
}
