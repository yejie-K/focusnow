#!/bin/zsh
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

chmod +x "$repo_root/.githooks/commit-msg"
chmod +x "$repo_root/.githooks/post-commit"
chmod +x "$repo_root/.githooks/pre-push"
chmod +x "$repo_root/scripts/update_dev_log.sh"

git config core.hooksPath .githooks
git config commit.template .gitmessage.txt

"$repo_root/scripts/update_dev_log.sh"

echo "Git 工作流已安装。"
echo "已启用提交信息校验、提交后自动开发日志、推送前自动测试。"
