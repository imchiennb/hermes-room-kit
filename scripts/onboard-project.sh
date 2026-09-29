#!/usr/bin/env bash
# onboard-project.sh — ONE entrypoint to bring any project into the room, new or long-running.
#
#   bash scripts/onboard-project.sh /path/to/project                       # facts + paste-ready brief
#   bash scripts/onboard-project.sh /path/to/project --run-tests           # also run the detected suite
#   bash scripts/onboard-project.sh /path/to/project --test-cmd "npm test" # use the project's real command
#   bash scripts/onboard-project.sh /path/to/project --mode new|existing   # override the auto-detection
#
# It writes two files into --out (default: ./baselines):
#   baseline-<slug>-<date>.md   machine facts: git state, baseline suite, repo shape, CI, rules
#   brief-<slug>-<date>.md      a paste-ready brief for the Supervisor seat + what to decide first
#
# Auto-detection (printed with its evidence, never silent):
#   NEW      = no git repo, or: no remote, <5 commits, first commit <7 days old, no CI config
#   EXISTING = has a remote, or >=5 commits, or first commit >=7 days old, or a CI config
#
# Nothing here mutates the project: read + report only.
set -uo pipefail

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJ=""
MODE=auto
RUN_TESTS=0
TEST_CMD=""
OUT="$KIT_DIR/baselines"

while [ $# -gt 0 ]; do
  case "$1" in
    --mode)       MODE="$2"; shift 2 ;;
    --run-tests)  RUN_TESTS=1; shift ;;
    --test-cmd)   TEST_CMD="$2"; shift 2 ;;
    --out)        OUT="$2"; shift 2 ;;
    -h|--help)    sed -n '2,20p' "$0"; exit 0 ;;
    -*)           echo "unknown option: $1" >&2; exit 2 ;;
    *)            PROJ="$1"; shift ;;
  esac
done

[ -n "$PROJ" ] || { sed -n '2,20p' "$0"; exit 2; }
PROJ="$(cd "$PROJ" 2>/dev/null && pwd)" || { echo "error: no such directory: $PROJ" >&2; exit 1; }
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
slug="$(basename "$PROJ")"
date_tag="$(date +%Y%m%d)"
baseline="$OUT/baseline-$slug-$date_tag.md"
brief="$OUT/brief-$slug-$date_tag.md"

# ---------------------------------------------------------------- facts
is_git=0
git -C "$PROJ" rev-parse --git-dir >/dev/null 2>&1 && is_git=1

commits=0; first_commit=""; head_sha=""; branch=""; remote=""; dirty=""; stashes=""
ci=""; age_days=""
if [ "$is_git" = 1 ]; then
  commits="$(git -C "$PROJ" rev-list --count HEAD 2>/dev/null || echo 0)"
  head_sha="$(git -C "$PROJ" rev-parse HEAD 2>/dev/null)"
  branch="$(git -C "$PROJ" rev-parse --abbrev-ref HEAD 2>/dev/null)"
  first_commit="$(git -C "$PROJ" log --reverse --format=%cs 2>/dev/null | head -1)"
  remote="$(git -C "$PROJ" remote -v 2>/dev/null | awk '{print $2}' | sort -u | head -1)"
  dirty="$(git -C "$PROJ" status --porcelain 2>/dev/null | wc -l)"
  stashes="$(git -C "$PROJ" stash list 2>/dev/null | wc -l)"
  for c in .github/workflows .gitlab-ci.yml .circleci Jenkinsfile azure-pipelines.yml; do
    [ -e "$PROJ/$c" ] && ci="$c" && break
  done
  if [ -n "$first_commit" ]; then
    age_days="$(python3 - "$first_commit" <<'PY'
import datetime, sys
try:
    print((datetime.date.today() - datetime.date.fromisoformat(sys.argv[1])).days)
except Exception:
    print(0)
PY
)"
  fi
fi

# ---------------------------------------------------------------- mode
reasons=()
detected="new"
if [ "$is_git" = 0 ]; then
  reasons+=("not a git repo")
else
  [ -n "$remote" ] && { detected="existing"; reasons+=("has a remote ($remote)"); }
  [ "${commits:-0}" -ge 5 ] && { detected="existing"; reasons+=("$commits commits"); }
  [ "${age_days:-0}" -ge 7 ] && { detected="existing"; reasons+=("history is ${age_days}d old"); }
  [ -n "$ci" ] && { detected="existing"; reasons+=("CI config: $ci"); }
  [ ${#reasons[@]} -eq 0 ] && reasons+=("no remote, few commits, young history")
fi
[ "$MODE" != auto ] && detected="$MODE"
mode_why="$(printf '%s; ' "${reasons[@]}")"

# ---------------------------------------------------------------- baseline (facts)
if [ "$is_git" = 1 ]; then
  run_args=()
  [ "$RUN_TESTS" = 1 ] && run_args+=(--run-tests)
  [ -n "$TEST_CMD" ] && run_args+=(--test-cmd "$TEST_CMD")
  bash "$KIT_DIR/scripts/onboard-repo.sh" "$PROJ" "${run_args[@]}" --out "$baseline" >/dev/null
else
  {
    printf '# Baseline report — %s (greenfield)\n' "$slug"
    printf '_generated %s_\n\n' "$(date +%Y-%m-%dT%H:%M:%S%z)"
    printf '## Not a git repo yet\n'
    printf -- '- path: `%s`\n' "$PROJ"
    printf -- '- action: `git init`, write README (product contract), commit the base, then re-run this script\n\n'
    printf '## Current contents\n'
    ls -A "$PROJ" 2>/dev/null | head -30 | while read -r f; do printf -- '- `%s`\n' "$f"; done
  } > "$baseline"
fi

# ---------------------------------------------------------------- brief (paste-ready)
{
  printf '# Onboard brief — %s (%s)\n\n' "$slug" "$detected"
  printf '_generated %s · baseline: `%s`_\n\n' "$(date +%Y-%m-%dT%H:%M:%S%z)" "$baseline"
  printf '## Facts (không suy diễn — đọc từ repo)\n\n'
  printf -- '- mode: **%s** — lý do: %s\n' "$detected" "$mode_why"
  printf -- '- path: `%s`\n' "$PROJ"
  if [ "$is_git" = 1 ]; then
    printf -- '- branch / HEAD: `%s` / `%s`\n' "$branch" "$head_sha"
    printf -- '- commits: %s · first commit: %s\n' "$commits" "${first_commit:-?}"
    printf -- '- remote: %s\n' "${remote:-(none)}"
    printf -- '- working tree: %s thay đổi · stash: %s\n' "${dirty:-?}" "${stashes:-?}"
  else
    printf -- '- **chưa phải git repo** → phải `git init` + commit base trước khi dispatch\n'
  fi
  printf '\n## 4 điều phải chốt với tôi (Human) trước khi dispatch\n\n'
  printf '1. **Môi trường chạy**: mọi thứ trong docker? app đã chạy sẵn (container nào / port nào)? cấm gì? — peer KHÔNG được tự start server hay chạy lệnh ngoài docker.\n'
  printf '2. **Dữ liệu test**: được ghi vào DB nào, và phải tự dọn + chứng minh residual = 0.\n'
  printf '3. **Acceptance chính thức**: lệnh nào là cổng nghiệm thu (chạy trong môi trường đã chốt).\n'
  printf '4. **Ai push/merge**: chỉ tôi. Room tuyệt đối không push; với dự án cũ thì không merge vào nhánh chính.\n'
  printf '\n## Dán khối dưới đây vào ghế Supervisor\n\n```text\n'
  printf 'Dự án: %s\n' "$PROJ"
  printf 'Loại: %s\n' "$detected"
  if [ "$is_git" = 1 ]; then
    printf 'Base commit: %s (nhánh %s)\n' "$head_sha" "$branch"
    printf 'Baseline: xem %s (đối chiếu acceptance: không được tệ hơn baseline)\n' "$baseline"
  else
    printf 'Trạng thái: chưa có git — Supervisor tạo repo, viết README = hợp đồng sản phẩm, commit base trước khi chia việc.\n'
  fi
  printf 'Mục tiêu: <mô tả outcome>\n'
  printf 'Phạm vi được chạm: <thư mục/file>\n'
  printf 'Không được chạm: <migrations, CI, lockfile, docs công khai, .env ...>\n'
  printf 'Acceptance: <lệnh test thật chạy trong môi trường đã chốt>\n'
  printf 'Việc cấm: không push; không tự start server; không chạy lệnh ngoài môi trường đã chốt\n'
  printf 'Yêu cầu quy trình: Lead phân rã thành các write scope độc lập, mỗi peer 1 worktree/branch, cả wave dispatch trong MỘT lượt; Lead review artifact từng peer (không nhận test xanh suông) và trả bài về đúng peer tới khi sạch; báo cáo kèm bằng chứng thô + timestamp chồng lấn.\n'
  printf '```\n'
  printf '\n## Mode-specific rules\n\n'
  if [ "$detected" = new ]; then
    cat <<'EOF'
**Dự án mới (greenfield)**
- Supervisor **sở hữu hợp đồng sản phẩm**: README ghi mục tiêu, phạm vi, acceptance (lệnh + hành vi), ràng buộc, ngoài phạm vi; commit base.
- Lead chốt `docs/CONTRACT.md` (interface, schema, mã lỗi, ranh giới file từng peer) rồi chia 2–4 module **rời nhau** để wave đầu chạy song song thật.
- Acceptance = suite xanh **gồm test end-to-end gọi CLI/API thật** + smoke test thật trong thư mục tạm.
- Merge vào nhánh chính của repo được (repo còn mới, chưa ai dùng) nhưng vẫn không push.
EOF
  else
    cat <<'EOF'
**Dự án đã chạy (brownfield)**
- **Không merge vào nhánh chính.** Lead merge vào nhánh tích hợp `room/<task-slug>`; tôi xem diff rồi tự merge/push vào nhánh thật.
- **Acceptance = không hồi quy**: baseline đỏ sẵn bao nhiêu case thì vẫn đúng bấy nhiêu (liệt kê ra), cấm "tiện tay sửa luôn"; tính năng mới thì thêm test mới, không sửa test cũ.
- **Quy tắc có sẵn trong repo thắng mặc định của room**: `AGENTS.md`/`CONTRIBUTING.md`/CI/style/lockfile — không reformat, không đổi dependency khi chưa được duyệt.
- **Write scope là file/thư mục cụ thể**, và chỉ những file thật sự độc lập mới chạy song song; dự án cũ thường 1 tính năng chạm nhiều file → ít peer hơn, không tách giả.
- Lead phải nêu sớm các blocker: env/secrets để chạy test, fixture/DB/service ngoài, test cần mạng hoặc quá chậm, submodule/code generate, vùng code đang có người khác sửa.
- Nếu working tree đang bẩn: commit hoặc stash trước khi dispatch (peer branch ra từ HEAD, phần chưa commit sẽ bị bỏ quên).
EOF
  fi
} > "$brief"

printf 'project : %s\nmode    : %s (%s)\n' "$PROJ" "$detected" "$mode_why"
printf 'baseline: %s\nbrief   : %s\n\n' "$baseline" "$brief"
printf 'Bước tiếp theo: mở brief, trả lời 4 điều ở mục "phải chốt", rồi dán khối text vào ghế Supervisor.\n'
