#!/bin/bash
# Claude Code 세션 자동 정리 (macOS)
#
# 오래 떠 있는 claude CLI 세션 프로세스를 종료해서
# "디렉터리가 한도에 도달했어요" 오류를 막는다.
# claude remote-control 서버와 Claude 데스크톱 앱은 건드리지 않는다.
#
# 사용법:
#   ./claude-cleanup.sh              지금 정리 (기본: 12시간 넘은 세션)
#   ./claude-cleanup.sh --dry-run    끌 대상만 보여주기
#   ./claude-cleanup.sh --hours 6    6시간 넘은 세션 정리
#   ./claude-cleanup.sh --install    매일 새벽 4시 자동 정리 등록 + 지금 1회 실행
#   ./claude-cleanup.sh --uninstall  자동 정리 해제

set -euo pipefail

HOURS=12
DRY_RUN=0
LABEL="com.user.claude-cleanup"
INSTALL_DIR="$HOME/.claude/bin"
INSTALLED="$INSTALL_DIR/claude-cleanup.sh"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG="$HOME/.claude/claude-cleanup.log"

# "[[dd-]hh:]mm:ss" 형식의 경과 시간을 초로 변환
etime_to_sec() {
  local t=$1 d=0 h=0 m=0 s=0
  if [[ $t == *-* ]]; then d=${t%%-*}; t=${t#*-}; fi
  IFS=: read -r -a p <<< "$t"
  case ${#p[@]} in
    3) h=${p[0]}; m=${p[1]}; s=${p[2]} ;;
    2) m=${p[0]}; s=${p[1]} ;;
    1) s=${p[0]} ;;
  esac
  echo $(( 10#$d*86400 + 10#$h*3600 + 10#$m*60 + 10#$s ))
}

cleanup() {
  local limit=$(( HOURS * 3600 )) killed=0
  echo "[$(date '+%F %T')] ${HOURS}시간 넘은 claude 세션 정리 시작"
  while read -r pid etime cmd; do
    [[ $pid == "$$" ]] && continue
    # CLI 세션만 대상: 실행 파일 이름이 claude 이거나 claude-code의 cli.js
    local exe=${cmd%% *}
    if [[ $(basename "$exe") != "claude" && $cmd != *claude-code/cli.js* ]]; then
      continue
    fi
    # 원격 접속 서버, 데스크톱 앱, 이 스크립트는 제외
    [[ $cmd == *remote-control* ]] && continue
    [[ $cmd == *Claude.app* ]] && continue
    [[ $cmd == *claude-cleanup* ]] && continue

    local age; age=$(etime_to_sec "$etime")
    (( age < limit )) && continue

    if (( DRY_RUN )); then
      echo "  [대상] PID $pid ($etime) ${cmd:0:120}"
    else
      echo "  [종료] PID $pid ($etime) ${cmd:0:120}"
      kill "$pid" 2>/dev/null || true
    fi
    killed=$((killed + 1))
  done < <(ps -axo pid=,etime=,command=)

  if (( DRY_RUN )); then
    echo "대상 ${killed}개 (dry-run, 실제로 끄지 않음)"
  else
    echo "${killed}개 세션 종료. 기록은 남아 있어 'claude --resume'으로 다시 열 수 있음"
  fi
}

install() {
  mkdir -p "$INSTALL_DIR" "$(dirname "$PLIST")"
  cp "$0" "$INSTALLED"
  chmod +x "$INSTALLED"
  cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>$INSTALLED</string>
    <string>--hours</string>
    <string>$HOURS</string>
  </array>
  <key>StartCalendarInterval</key>
  <dict><key>Hour</key><integer>4</integer><key>Minute</key><integer>0</integer></dict>
  <key>StandardOutPath</key><string>$LOG</string>
  <key>StandardErrorPath</key><string>$LOG</string>
</dict>
</plist>
PLIST
  launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
  launchctl bootstrap "gui/$(id -u)" "$PLIST"
  echo "자동 정리 등록 완료: 매일 04:00, ${HOURS}시간 넘은 세션 종료 (로그: $LOG)"
  echo
  cleanup
}

uninstall() {
  launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
  rm -f "$PLIST" "$INSTALLED"
  echo "자동 정리 해제 완료"
}

ACTION=cleanup
while (( $# )); do
  case $1 in
    --dry-run)   DRY_RUN=1 ;;
    --hours)     HOURS=$2; shift ;;
    --install)   ACTION=install ;;
    --uninstall) ACTION=uninstall ;;
    -h|--help)   sed -n '2,15p' "$0"; exit 0 ;;
    *) echo "알 수 없는 옵션: $1" >&2; exit 1 ;;
  esac
  shift
done

$ACTION
