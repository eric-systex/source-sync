#!/bin/bash

# --- 參數檢查 ---
if [ "$#" -ne 3 ]; then
    echo "Usage: $0 <repo_name> <source_repo_path> <target_repo_path>"
    exit 1
fi

name="$1"
source="$2"
target="$3"
working_home=~/projects/gemma/source-sync
temp_repo="$working_home/temp/$name"
token="this-is-secret" 

# --- 函數: 發送通知 ---
send_sns() {
    local subject="$1"
    local message="$2"
    aws sns publish --profile misystex --topic-arn arn:aws:sns:ap-southeast-1:1234567890:sync-source --subject "FCB $subject" --message "$message"
}

# --- 工作目錄設置 ---
mkdir -p "$working_home/temp"
rm -rf "$temp_repo"
mkdir -p "$temp_repo"

current_date=$(date +"%Y-%m-%d %H:%M:%S")
echo "現在時間: $current_date"

# --- 倉庫 URL 設置 ---
#source_repo="https://misystexuser:misystexuser3edc@192.168.68.231/$source"
source_repo="ssh://git-codecommit.ap-southeast-1.amazonaws.com/v1/repos/$source"
target_repo_sensitive="https://oauth2:$token@git.systex.com/$target"
target_repo="https://oauth2:**********@git.systex.com/$target"

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
#if ! git push --all target || ! git push --tags target; then
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
result_file="$working_home/result.tmp"
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
