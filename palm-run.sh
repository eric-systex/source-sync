#!/bin/bash

BASE_DIR=~/projects/palm/source-sync
LOG_DIR="$BASE_DIR/logs"
SCRIPT="$BASE_DIR/sync.sh"

# 建立 log 資料夾（如果不存在）
mkdir -p "$LOG_DIR"

# target 名稱與對應的路徑（平行陣列）
TARGETS=(
  "framework"
  "framework-example"
  "channel-example"
  "service-example"
  "service-sagaexample"
  "acl-example"
  "service-empty"
  "environment-example"
  "portal-framework"
  "backend-framework"
)

PATHS=(
  "2023_23MF31R/i3mf33k23070001"
  "misystex/999_Other/misys_framework/luzmi_framework-example"
  "misystex/999_Other/misys_framework/luzmi_channel-example"
  "misystex/999_Other/misys_framework/luzmi_service-example"
  "misystex/999_Other/misys_framework/luzmi_service-sagaexample"
  "misystex/999_Other/misys_framework/luzmi_acl-example"
  "misystex/999_Other/misys_framework/luzmi_service-empty"
  "misystex/999_Other/misys_framework/luzmi_environment-example"
  "i3mf33k23070002/luzmi-portal_frontend"
  "i3mf33k23070002/luzmi-protal_backend"
)

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

  aws sns publish \
    --profile misystex \
    --topic-arn arn:aws:sns:ap-southeast-1:1234567890:sync-source \
    --subject "LuzMi $subject" \
    --message "$message"
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
  send_sns "$subject" "$message"

  if [ $? -eq 0 ]; then
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
  local path="$2"
  local log="$LOG_DIR/sync_${name}.log"

  TOTAL=$((TOTAL + 1))

  echo "🔄 執行同步：$name"
  echo "📁 路徑：$path"
  echo "📝 Log：$log"

  $SCRIPT "$name" "$path" >> "$log" 2>&1

  if [ $? -eq 0 ]; then
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
# 若沒參數或參數為 --all，執行所有項目
# ============================================================

if [ -z "$1" ] || [ "$1" == "--all" ]; then
  echo "🚀 執行全部同步任務..."
  for i in "${!TARGETS[@]}"; do
    run_sync "${TARGETS[$i]}" "${PATHS[$i]}"
  done
  echo "✅ 全部同步完成"
  exit 0
fi

# ============================================================
# 單項執行
# ============================================================

TARGET_INPUT="$1"
FOUND=0

for i in "${!TARGETS[@]}"; do
  if [ "$TARGET_INPUT" == "${TARGETS[$i]}" ]; then
    run_sync "${TARGETS[$i]}" "${PATHS[$i]}"
    FOUND=1
    break
  fi
done

if [ "$FOUND" -eq 0 ]; then
  echo "❌ 無效的目標名稱：$TARGET_INPUT"
  echo "可用選項：${TARGETS[*]}"

  # 無效參數不屬於同步執行結果，因此不寄送通知
  NOTIFICATION_SENT=1

  exit 1
fi

