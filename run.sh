#!/bin/bash

# --- 參數檢查 ---
if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
    echo "Usage: $0 <project> [repo_name|--all]"
    exit 1
fi

PROJECT="$1"
CONFIG_FILE="conf/${PROJECT}.conf"
TARGET_INPUT="${2:---all}"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "找不到設定檔: $CONFIG_FILE"
    exit 1
fi
# shellcheck disable=SC1090
source "$CONFIG_FILE"

for v in AWS_ACCOUNT_ID AWS_PROFILE_NAME AWS_REGION SNS_SUBJECT_PREFIX TOKEN; do
    if [ -z "${!v}" ]; then
        echo "設定檔缺少參數: $v"
        exit 1
    fi
done
if [ "${#REPOS[@]}" -eq 0 ]; then
    echo "設定檔缺少 REPOS"
    exit 1
fi

BASE_DIR="${HOME}/projects/source-sync"
LOG_DIR="$BASE_DIR/logs"
SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/sync.sh"
CONFIG_ABS="$(cd "$(dirname "$CONFIG_FILE")" && pwd)/$(basename "$CONFIG_FILE")"
TOPIC_ARN="arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:sync-source"

mkdir -p "$LOG_DIR"

# 解析 REPOS (name|source_path|target_path)
NAMES=()
SOURCE_PATHS=()
TARGET_PATHS=()
for entry in "${REPOS[@]}"; do
  IFS='|' read -r n s t <<< "$entry"
  NAMES+=("$n")
  SOURCE_PATHS+=("${s:-$n}")
  TARGET_PATHS+=("$t")
done

# ============================================================
# 執行結果統計
# ============================================================

TOTAL=0
SUCCESS_COUNT=0
FAILED_COUNT=0

SUCCESS_LIST=()
FAILED_LIST=()

INTERRUPTED=0
NOTIFICATION_SENT=0


# ============================================================
# 函數: 發送通知
# ============================================================

send_sns() {
  local subject="$1"
  local message="$2"
  aws sns publish --profile "$AWS_PROFILE_NAME" --region "$AWS_REGION" --topic-arn "$TOPIC_ARN" --subject "$SNS_SUBJECT_PREFIX $subject" --message "$message"
}


# ============================================================
# 函數: 發送最終結果通知
# ============================================================

send_summary() {

  # 避免 EXIT trap 與 signal trap 重複寄送
  if [ "$NOTIFICATION_SENT" -eq 1 ]; then
    return
  fi

  NOTIFICATION_SENT=1

  local subject="源碼同步統計 - 總數:${TOTAL} /成功:${SUCCESS_COUNT} /失敗:${FAILED_COUNT}"
  local message="源碼同步執行結果

總數：${TOTAL}
成功數：${SUCCESS_COUNT}
失敗數：${FAILED_COUNT}
"

  if [ "$INTERRUPTED" -eq 1 ]; then
    message="${message}
⚠️ 執行過程被中斷
"
  fi

  message="${message}
========================================
失敗清單
========================================
"

  if [ "$FAILED_COUNT" -eq 0 ]; then
    message="${message}無
"
  else
    for item in "${FAILED_LIST[@]}"; do
      message="${message}- ${item}
"
    done
  fi

  message="${message}
========================================
成功清單
========================================
"

  if [ "$SUCCESS_COUNT" -eq 0 ]; then
    message="${message}無
"
  else
    for item in "${SUCCESS_LIST[@]}"; do
      message="${message}- ${item}
"
    done
  fi

  echo ""
  echo "📧 發送同步結果通知..."
  if send_sns "$subject" "$message"; then
    echo "📧 通知發送成功"
  else
    echo "⚠️ 通知發送失敗"
  fi
}


# ============================================================
# 函數: 處理程序中斷
# ============================================================

handle_interrupt() {

  local signal="$1"

  echo ""
  echo "⚠️ 收到 ${signal}，即將結束程式..."

  INTERRUPTED=1

  # 使用 exit，讓 EXIT trap 最後統一寄送通知
  exit 130
}


# ============================================================
# Trap
#
# EXIT   ：正常結束 / exit
# SIGINT ：Ctrl+C
# SIGTERM：kill
# ============================================================

trap 'send_summary' EXIT
trap 'handle_interrupt SIGINT' SIGINT
trap 'handle_interrupt SIGTERM' SIGTERM


# ============================================================
# 函數: 執行同步
# ============================================================

run_sync() {
  local name="$1"
  local source="$2"
  local target="$3"
  local log="$LOG_DIR/sync_${name}.log"

  TOTAL=$((TOTAL + 1))

  echo "🔄 執行同步：$name"
  echo "📁 來源：$source"
  echo "📁 目標：$target"
  echo "📝 Log：$log"

  if "$SCRIPT" "$CONFIG_ABS" "$name" "$source" "$target" >> "$log" 2>&1; then
    echo "✅ 同步成功：$name"
    SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    SUCCESS_LIST+=("$name")
  else
    echo "❌ 同步失敗：$name ，請查看日誌：$log"
    FAILED_COUNT=$((FAILED_COUNT + 1))
    FAILED_LIST+=("$name")
  fi
  echo "---------------------------------------"
}

# ============================================================
# 全部執行
# ============================================================

if [ "$TARGET_INPUT" == "--all" ]; then
  echo "🚀 執行全部同步任務..."
  for i in "${!NAMES[@]}"; do
    run_sync "${NAMES[$i]}" "${SOURCE_PATHS[$i]}" "${TARGET_PATHS[$i]}"
  done
  echo "✅ 全部同步完成"
  exit 0
fi

# ============================================================
# 單項執行
# ============================================================

FOUND=0

for i in "${!NAMES[@]}"; do
  if [ "$TARGET_INPUT" == "${NAMES[$i]}" ]; then
    run_sync "${NAMES[$i]}" "${SOURCE_PATHS[$i]}" "${TARGET_PATHS[$i]}"
    FOUND=1
    break
  fi
done

if [ "$FOUND" -eq 0 ]; then
  echo "❌ 無效的目標名稱：$TARGET_INPUT"
  echo "可用選項：${NAMES[*]}"

  # 無效參數不屬於同步執行結果，因此不寄送通知
  NOTIFICATION_SENT=1

  exit 1
fi
