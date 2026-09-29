# hermes-room-kit

Bộ cài cho **agent room** của anh: Supervisor → nhiều Lead theo domain → Peer, chạy trên Paseo Desktop + Hermes.
Kit này trả lời 2 việc:

| Việc | Đọc gì |
|---|---|
| **Dùng room cho một dự án khác** | [`docs/NEW-PROJECT.md`](docs/NEW-PROJECT.md) |
| **Dựng room trên máy mới** | phần "Máy mới" ngay dưới đây |

Nguồn sự thật của kit là **máy đang chạy room** — sau mỗi lần cải tiến skill/brief, chạy `bash scripts/capture.sh` để cập nhật kit, rồi `git commit`.

---

## Máy mới — 5 bước

```bash
# 1. Cài Hermes (bắt buộc) và Paseo Desktop (bắt buộc để có UI + daemon)
#    Hermes: theo hướng dẫn cài của anh (installer/script) — kiểm tra: hermes --version
#    Paseo:  https://paseo.sh/download  → mở app 1 lần cho nó tự dựng daemon

# 2. Lấy kit về máy mới (git clone, scp, hay copy cả thư mục đều được)

# 3. Cài đặt (idempotent — chạy lại nhiều lần không sao)
cd hermes-room-kit
bash install.sh                 # thêm --dry-run để xem trước, không ghi gì

# 4. Điền API key cho từng profile (install.sh đã tạo sẵn file .env trống)
#    ~/.hermes/profiles/{supervisor,lead,peer}/.env   →  SWICLOUD_API_KEY=...

# 5. Kiểm tra
bash verify.sh                  # kỳ vọng: "20 passed, 0 failed"
```

Sau đó mở Paseo Desktop: trong danh sách provider/agent sẽ có **Supervisor / Lead / Peer** (provider `hermes-supervisor`, `hermes-lead`, `hermes-peer`).

`install.sh` cài:
- 3 profile Hermes (`config.yaml` + `AGENTS.md` — bản hợp đồng vai trò)
- Hợp đồng dùng chung: `~/.hermes/profiles/WORKFLOW.md`, `PROMPT_TEMPLATES.md`
- 3 skill của room: `paseo-room-supervisor` (supervisor), `paseo-lead-orchestration` (lead), `scoped-change-briefs` (peer)
- Mục provider + agent profile trong `~/.paseo/config.json` (**merge**, không thay cả file; tự backup)

Nó **không** copy: `.env` (secret), `state.db`, sessions, memories, cache, log, worktree.

### Muốn mang theo cả trí nhớ / lịch sử session (tuỳ chọn)

```bash
# TRÊN MÁY CŨ
bash scripts/carry-state.sh capture --with-history --with-secrets
#   -> state/room-state-<seat>.tar.gz  (memories + cron + hooks + plugins + SOUL.md
#      + snapshot state.db + .env). Bỏ 2 cờ đó thì chỉ mang memories/cron/hooks/plugins.

# copy thư mục state/ sang máy mới (cùng chỗ với kit), rồi:
bash install.sh
bash scripts/carry-state.sh restore --with-history --with-secrets
```

Ghi chú thật:
- `.env` chứa API key → `state/` phải nằm ngoài git (đã có trong `.gitignore`), copy bằng scp/USB, xong thì xoá.
- `hermes profile export/import` (đường native) **hiện lỗi** với các profile này: archive chứa symlink (`skills/skills`, `lsp/bin/pyright-langserver`) nên import báo `Unsupported archive member type`. Mình đã test cả 3 ghế — dùng `carry-state.sh` thay thế.

### Nếu máy mới không có `paseo` CLI

Không sao. `install.sh` sẽ nhắc: đóng và mở lại **Paseo Desktop** để nạp config mới — làm lúc **không có agent nào đang chạy** (restart daemon sẽ kill agent đang chạy). Có `paseo` CLI thì dùng `paseo daemon reload` (không kill agent).

---

## Máy đang chạy → kit (giữ kit khớp thực tế)

```bash
cd hermes-room-kit
bash scripts/capture.sh          # chụp lại profiles + skills + fragment Paseo từ máy này
git diff                          # xem thay đổi, commit
```

---

## Paseo MCP + gotcha

- Mỗi `tool_call` chỉ chứa **1 lệnh MCP** local (batch >1 bị reject) — nhưng **cả wave trong cùng một lượt**.
- Worktree của peer nằm ở `~/.paseo/worktrees/<id>/peer-<scope>`.
- ⚠️ Repo `codex-room-setup` **ghi đè toàn bộ** `~/.paseo/config.json` (mất ghế hermes-*) và tạo link `~/.local/bin/paseo`. Không dùng trừ khi anh thật sự muốn ghế Codex. Kit này chỉ merge đúng 3 provider `hermes-*`.
