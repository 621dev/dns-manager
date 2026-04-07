#!/bin/bash

clear

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
DATA_DIR="$SCRIPT_DIR/data"
LOG_FILE="$DATA_DIR/dns_manager.log"
DNS_IP=$(ip route get 1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}' | head -1)
DNS_TYPE="none"
DNS_RUNNING="false"

# data 디렉토리 초기화
mkdir -p "$DATA_DIR"

source "$SCRIPT_DIR/dns_crud_docker.sh"
source "$SCRIPT_DIR/dns_setting_docker.sh"
source "$SCRIPT_DIR/zone_manager_docker.sh"

if [ ! -f "$LOG_FILE" ]; then
    touch "$LOG_FILE"
    echo "$(date '+%Y%m%d %H%M%S') - DNS 매니저 로그 파일 생성됨" > "$LOG_FILE"
fi

# 메인 메뉴
while :
do
    sleep 2 && clear
    echo "==============================================="

    # named 실행 여부로 설치 상태 판단 (도커에서는 항상 패키지 존재)
    DNS_RUNNING=$(is_named_running)

    if [ "$DNS_RUNNING" == "true" ]; then
        echo "DNS 서비스 실행 중"
        echo "서비스 상태 : 실행 중"

        DNS_TYPE=$(get_dns_type)
        case $DNS_TYPE in
            master) echo "서버 타입   : Master" ;;
            slave)  echo -e "서버 타입   : Slave \n named.rfc1912.zones를 마스터 서버와 동기화하려면 declupdate를 입력해주세요." ;;
            none)   echo "서버 타입   : none" ;;
            *)      echo "서버 타입   : 알 수 없음" ;;
        esac
    else
        echo "DNS 서비스 중지됨"
        echo "서비스 상태 : 중지됨 (시작하려면 startDNS를 입력하세요.)"
    fi

    echo "==============================================="
    echo "1. DNS 서비스 설치"
    echo "2. DNS 서비스 정리"
    echo "3. DNS 설정"
    echo "4. Zone 관리"
    echo "q. 종료"
    echo "==============================================="
    read -p "원하는 작업을 선택하세요: " INPUT

    if [ "$INPUT" == "q" ]; then exit 0; fi

    if [[ "$DNS_RUNNING" == "false" && "$INPUT" == "startDNS" ]]; then
        named -u named -f -c /etc/named.conf &>> "$LOG_FILE" &
        echo "DNS가 시작되었습니다. (PID: $!)"
        continue
    fi

    if [[ "$DNS_TYPE" == "slave" && "$INPUT" == "declupdate" ]]; then
        reload_dns_decl
        continue
    fi

    if [ "$DNS_RUNNING" == "true" ]; then
        case $INPUT in
            1)
                echo "DNS 서비스가 이미 실행 중입니다. 정리 후 다시 초기화해주세요."
                ;;
            2)
                delete_named
                ;;
            3)
                set_dns
                ;;
            4)
                manage_zone
                ;;
            *)
                echo "잘못된 입력입니다. 다시 시도해주세요."
                ;;
        esac
    else
        case $INPUT in
            1)
                install_named
                ;;
            2|3|4)
                echo "DNS 서비스를 먼저 초기화해주세요."
                ;;
            *)
                echo "잘못된 입력입니다. 다시 시도해주세요."
                ;;
        esac
    fi
done
