#!/bin/bash

# --- 參數檢查 ---
if [ "$#" -ne 4 ]; then
    echo "Usage: $0 <config_file> <repo_name> <source_repo_path> <target_repo_path>"
    exit 1
fi

config_file="$1"
name="$2"
source="${3:-$2}"
target="$4"

if [ ! -f "$config_file" ]; then
    echo "找不到設定檔: $config_file"
    exit 1
fi
# shellcheck disable=SC1090
source "$config_file"

for v in AWS_ACCOUNT_ID AWS_PROFILE_NAME AWS_REGION SNS_TOPIC_NAME SNS_SUBJECT_PREFIX \
         TOKEN WORKING_HOME SOURCE_URL_BASE TARGET_URL_BASE; do
    if [ -z "${!v}" ]; then
        echo "設定檔缺少參數: $v"
        exit 1
    fi
done

working_home="$WORKING_HOME"
temp_repo="$working_home/temp/$name"
token="$TOKEN"
topic_arn="arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${SNS_TOPIC_NAME}"

# --- 函數: 發送通知 ---
send_sns() {
    local subject="$1"
    local message="$2"
    aws sns publish --profile "$AWS_PROFILE_NAME" --region "$AWS_REGION" --topic-arn "$topic_arn" --subject "$SNS_SUBJECT_PREFIX $subject" --message "$message"
}

# --- 工作目錄設置 ---
mkdir -p "$working_home/temp"
rm -rf "$temp_repo"
mkdir -p "$temp_repo"

current_date=$(date +"%Y-%m-%d %H:%M:%S")
echo "現在時間: $current_date"

# --- 倉庫 URL 設置 ---
source_repo="$SOURCE_URL_BASE/$source"
target_repo_sensitive="$TARGET_URL_BASE/$target"
target_repo="$TARGET_URL_BASE/$target"

echo "來源 GitLab 倉庫的 URL: $source_repo"
echo "目標 GitLab 倉庫的 URL: $target_repo"

# --- 克隆來源倉庫 ---
echo
echo "克隆來源 GitLab 倉庫到本地"
if ! git clone --quiet --mirror "$source_repo" "$temp_repo/source_mirror"; then
    send_sns "源碼同步失敗(優化版) $name" "來源克隆失敗 $source_repo"
    exit 1
fi

cd "$temp_repo/source_mirror"

# --- 推送所有分支到目標倉庫 ---
echo
echo "推送所有分支到目標 GitLab 倉庫"
if ! git remote add target "$target_repo_sensitive"; then
    git remote set-url target "$target_repo_sensitive"
fi

if ! git push --mirror target; then
    send_sns "源碼同步失敗(優化版) $name" "推送到目標倉庫失敗 $target_repo"
    exit 1
fi

# --- 統計來源分支提交數 ---
source_total_commits=$(git rev-list --all --count)

# --- 清理並克隆目標倉庫 ---
echo
echo "清理"
cd "$working_home"
rm -rf "$temp_repo/target_mirror"
echo
echo "克隆目標 GitLab 倉庫到本地"
if ! git clone --quiet --mirror "$target_repo_sensitive" "$temp_repo/target_mirror"; then
    send_sns "源碼同步失敗(優化版) $name" "目標克隆失敗 $target_repo"
    exit 1
fi

cd "$temp_repo/target_mirror"
target_total_commits=$(git rev-list --all --count)

echo
echo "來源 $source_total_commits commits"
echo "目標 $target_total_commits commits"

# --- 結果通知 ---
result_file="$working_home/result.$name.tmp"
echo "來源 $source_total_commits commits" > "$result_file"
echo "目標 $target_total_commits commits" >> "$result_file"

if [ "$source_total_commits" -ne "$target_total_commits" ]; then
    send_sns "源碼同步失敗(優化版) $name" "file://$result_file"
    exit_code=1
else
    send_sns "源碼同步成功(優化版) $name" "file://$result_file"
    exit_code=0
fi

# --- 最終清理 ---
echo
echo "清理"
cd "$working_home"
rm -rf "$temp_repo"
rm -f "$result_file"

echo "完成"
exit "$exit_code"
