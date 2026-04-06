# DNS Manager - Docker 환경 전환 가이드

## 개요

기존 `dns-manager` 스크립트는 베어메탈/VM 환경의 Rocky Linux(RHEL 계열)를 전제로 작성되었습니다.
도커 컨테이너 환경에서는 `systemctl`, `firewall-cmd`, `SELinux`, `rpm` 등이 사용 불가능하거나 불필요하므로, 해당 요소들을 제거하거나 대체한 도커 전용 스크립트를 별도 생성했습니다.

---

## 파일 구성

```
dns-manager/docker/
├── Dockerfile
├── dns_manager_docker.sh     # 엔트리포인트 (메인 메뉴)
├── dns_crud_docker.sh        # BIND 설치/삭제/상태 확인
├── dns_setting_docker.sh     # DNS 설정 (slave 등록, named.conf 수정 등)
├── zone_manager_docker.sh    # Zone 관리 메뉴 및 유틸리티 함수
├── zone_crud_docker.sh       # Zone CRUD (선언/파일 생성·삭제·수정)
└── docker-dns-manager.md     # 이 문서
```

---

## 주요 변경사항

### 1. `systemctl` → 프로세스 직접 관리

도커 컨테이너는 `systemd`를 init 프로세스로 사용하지 않으므로 `systemctl`이 동작하지 않습니다.

| 원본 | 도커 전환 |
|------|-----------|
| `systemctl start named` | `named -c /etc/named.conf &` |
| `systemctl is-active --quiet named` | `pgrep -x named > /dev/null 2>&1` |
| `systemctl` 기반 재시작 | `rndc reload` 또는 `kill -HUP $(pgrep named)` |

`_named_reload()` 헬퍼 함수를 `dns_setting_docker.sh`에 추가해 `rndc reload` 실패 시 `SIGHUP` 폴백을 처리합니다.

```bash
# dns_setting_docker.sh
_named_reload() {
    if pgrep -x named > /dev/null 2>&1; then
        if rndc reload &>> "$LOG_FILE"; then
            echo "named 설정이 재로드되었습니다."
        else
            kill -HUP $(pgrep -x named)
            echo "named 설정이 SIGHUP으로 재로드되었습니다."
        fi
    else
        echo "named가 실행 중이지 않습니다. 재로드를 건너뜁니다."
    fi
}
```

---

### 2. `rpm -qa bind` → `pgrep named` (설치 여부 판단 변경)

원본 스크립트는 `rpm -qa bind`로 BIND 패키지 설치 여부를 확인해 메뉴를 분기했습니다.
도커 이미지에는 BIND가 항상 설치된 상태로 빌드되므로, **named 프로세스 실행 여부**로 서비스 상태를 판단합니다.

| 원본 | 도커 전환 |
|------|-----------|
| `rpm -qa bind` | `pgrep -x named` |
| "DNS 서비스 설치됨" 분기 | "DNS 서비스 실행 중" 분기 |
| 메뉴 1: DNS 설치 | 메뉴 1: DNS 초기화 (named.conf 설정 적용 및 기동) |
| 메뉴 2: DNS 삭제 | 메뉴 2: DNS 정리 (프로세스 종료 + 설정 초기화) |

---

### 3. `firewall-cmd` 제거

도커에서는 호스트의 방화벽(`firewalld`)이 컨테이너 네트워크를 담당합니다.
컨테이너 내부에서 `firewall-cmd`를 실행해도 효과가 없고, 실행 자체가 불가능한 경우가 대부분입니다.

> **대신:** `Dockerfile`에서 `EXPOSE 53/tcp`와 `EXPOSE 53/udp`를 선언하고,
> `docker run` 시 `-p 53:53/tcp -p 53:53/udp` 옵션으로 포트를 노출합니다.

---

### 4. `SELinux` 처리 제거

컨테이너 내부에서는 SELinux가 비활성(`Disabled`) 상태이므로 `getenforce`, `semanage` 명령이 불필요합니다.

---

### 5. `hostname -I` → `ip route` 기반 IP 취득

`hostname -I`는 환경에 따라 빈 문자열을 반환할 수 있습니다. 도커 컨테이너의 IP는 `ip route`로 안정적으로 가져옵니다.

```bash
# 원본
DNS_IP=$(hostname -I | awk '{print $1}')

# 도커 전환
DNS_IP=$(ip route get 1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}' | head -1)
```

---

### 6. 데이터 경로 통합 (`data/` 서브디렉토리)

원본에서 `dns_data.txt`, 로그 파일, 백업 디렉토리는 모두 `SCRIPT_DIR` 루트에 위치했습니다.
도커에서는 `VOLUME`으로 마운트 관리가 용이하도록 `data/` 하위로 통합했습니다.

| 원본 경로 | 도커 전환 경로 |
|-----------|----------------|
| `$SCRIPT_DIR/dns_data.txt` | `$SCRIPT_DIR/data/dns_data.txt` |
| `$SCRIPT_DIR/dns_manager.log` | `$SCRIPT_DIR/data/dns_manager.log` |
| `$SCRIPT_DIR/dns_backup_*` | `$SCRIPT_DIR/data/dns_backup_*` |

---

### 7. `yum` → `dnf` (Dockerfile 기준)

Rocky Linux 9 기반 이미지를 사용하므로 패키지 설치는 `dnf`를 사용합니다.
스크립트 내부에서 런타임 설치는 없으며, Dockerfile에서 빌드 타임에 설치합니다.

```dockerfile
RUN dnf install -y bind bind-utils iproute procps-ng util-linux && dnf clean all
```

---

## 사용 방법

### 빌드 및 실행

```bash
# docker/ 디렉토리에서 실행
cd linux-server/dns-manager/docker/

# 이미지 빌드
docker build -t dns-manager .

# 컨테이너 실행 (인터랙티브, 포트 노출, 데이터 볼륨 마운트)
docker run -it \
  -p 53:53/tcp \
  -p 53:53/udp \
  -v dns-manager-data:/opt/dns-manager/data \
  -v dns-named-conf:/etc/named \
  -v dns-named-zones:/var/named \
  --cap-add=NET_ADMIN \
  --name dns-manager \
  dns-manager
```

> `--cap-add=NET_ADMIN` : `rndc`, `ip route` 명령 실행에 필요한 네트워크 권한

### docker-compose 예시

```yaml
services:
  dns-manager:
    build: .
    ports:
      - "53:53/tcp"
      - "53:53/udp"
    volumes:
      - dns-data:/opt/dns-manager/data
      - named-conf:/etc/named
      - named-zones:/var/named
    cap_add:
      - NET_ADMIN
    stdin_open: true
    tty: true

volumes:
  dns-data:
  named-conf:
  named-zones:
```

---

## 변경되지 않은 요소

- Zone 선언 생성/삭제 로직 (`create_zone_declaration`, `delete_zone_declaration`)
- Zone 파일 생성/수정/삭제 로직 (A 레코드, PTR 레코드)
- slave 서버 동기화 로직 (`ssh` 기반 `named.rfc1912.zones` 수신)
- IP 유효성 검사 (`check_ip`)
- Serial 번호 갱신 (`update_serial`, `update_decl_serial`)
- 페이지네이션 UI (`show_zone_list`, `show_service_list`)
