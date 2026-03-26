# DNS Manager

Rocky Linux(RHEL 계열) 환경에서 BIND DNS 서버를 관리하는 Bash 스크립트 모음입니다.

## 요구사항

- Red Hat 계열 Linux (Rocky Linux 8+ 권장)
- root 권한

## 파일 구성

| 파일 | 설명 |
|------|------|
| `dns_manager.sh` | 메인 진입점 |
| `dns_crud.sh` | DNS 서비스(named) 설치 / 삭제 |
| `zone_manager.sh` | Zone 목록 조회 및 페이지네이션 UI |
| `zone_crud.sh` | Zone 추가 / 삭제 |

## 사용법

```bash
sudo bash dns_manager.sh
```

## 주요 기능

- BIND(named) 서비스 설치 및 삭제
- 정방향 Zone 추가 / 삭제
- 역방향 Zone 추가 / 삭제
- 삭제 및 덮어쓰기 전 자동 백업 (`dns_backup_YYYYMMDD/`)

## 미구현 항목

- Zone 상세 조회
- Zone 수정
- 페이지 네비게이션 (`[` `]` `:숫자`)
- DNS 설정
- 방화벽 포트 관리
