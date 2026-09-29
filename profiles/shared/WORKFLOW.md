# Multi-Agent Workflow Guide

## Architecture

```
Human (anh)
  └── Supervisor  ← entry point cho mọi task phức tạp
        ├── Lead  ← thực thi kỹ thuật
        └── Peer  ← review độc lập (do Lead hoặc Supervisor gọi)
```

---

## Khi nào dùng role nào

| Tình huống | Role |
|---|---|
| Task đơn giản, rõ ràng, ít rủi ro | Gửi thẳng **Lead** |
| Task phức tạp, nhiều bước, cần điều phối | Gửi **Supervisor** |
| Muốn review độc lập trước khi merge/deploy | **Supervisor** hoặc **Lead** gọi **Peer** |
| Bug rõ nguyên nhân | Gửi thẳng **Lead** |
| Bug không rõ, cần điều tra nhiều hướng | **Supervisor** → spawn nhiều **Lead** song song |
| Code review PR | **Peer** (read-only, không side effect) |
| Quyết định kiến trúc | **Supervisor** → **Lead** đề xuất → **Peer** phản biện → anh quyết |

---

## Workflow chuẩn: Task phức tạp

### 1. Anh → Supervisor

Gửi vào Supervisor profile trong Paseo:

```
Task: Refactor module auth để support OAuth2 + JWT
Context: repo tại ~/myproject, tests ở tests/auth/
Constraint: không break API cũ
```

### 2. Supervisor phân rã → Lead

Supervisor tự `delegate_task` hoặc hướng dẫn Lead:

```
Lead: implement OAuth2 handler + JWT middleware
- File: src/auth/oauth.py, src/auth/jwt.py
- Phải pass tests/auth/
- Return: candidate commit hash + test output
```

### 3. Lead thực thi → Peer review (nếu cần)

Lead tự quyết khi nào cần Peer. Trigger khi:
- Logic phức tạp, nhiều edge case
- Security-sensitive code
- Không chắc approach đúng

Lead gửi sang Peer:
```
Review: src/auth/oauth.py (commit abc123)
Context: OAuth2 flow, JWT signing với RS256
Check: token expiry logic, refresh flow, error handling
```

### 4. Peer trả verdict

```
ACCEPT: Token expiry check đúng. Refresh flow handle edge case expired+blacklisted. 
        JWT signing dùng RS256 với key rotation safe.

-- hoặc --

BLOCK: jwt.py:47 — decode không verify `aud` claim.
       Attacker dùng token từ service khác pass được.
       Fix: thêm audience=["myapp"] vào jwt.decode()
```

### 5. Supervisor tổng hợp → Human

```
Lead đã implement OAuth2+JWT. Peer ACCEPT với 0 block.
Tests: 24/24 pass. 
Candidate: commit abc123
Cần anh review diff trước khi merge? [Y/N]
```

---

## Truyền context giữa agents

### Cách 1: File trung gian (đơn giản nhất)

```bash
# Lead ghi output ra file
echo "API schema: ..." > /tmp/handoff-lead-to-peer.md

# Peer đọc file đó
# Supervisor reference đường dẫn trong prompt
```

### Cách 2: Git worktree (parallel tasks)

```bash
# Supervisor tạo worktree per task
git worktree add -b fix/auth ~/.hermes/cache/scratch/auth main
git worktree add -b fix/db  ~/.hermes/cache/scratch/db  main

# Lead-1 làm auth trong scratch/auth
# Lead-2 làm db trong scratch/db
# Chạy song song, không conflict
```

### Cách 3: Paste trực tiếp trong Paseo

Khi Supervisor cần pass output của Lead sang Peer:
- Copy output từ Lead tab
- Paste vào Peer tab kèm instruction

---

## Quy tắc bất biến

| Rule | Lý do |
|---|---|
| Human quyết định mọi irreversible action | Deploy, delete data, push to main |
| Peer không được write/commit | Review độc lập mất giá trị nếu Peer sửa code |
| Lead phải chạy test trước khi return candidate | Supervisor không verify lại từ đầu |
| Supervisor không implement — chỉ route và tổng hợp | Tránh scope creep, giữ vai trò rõ ràng |
| Block signal phải cụ thể | "có vấn đề" không phải block signal |

---

## Shortcut: Task đơn giản không cần Supervisor

```
Lead (trực tiếp):
  "Fix bug: TypeError ở src/api/users.py:134, 
   users không có attribute 'email' khi register qua OAuth"
```

Không cần Supervisor khi:
- Task bounded, rõ ràng
- 1 file hoặc 1 module
- Không cần coordination
- Anh đã biết chính xác cần làm gì

---

## Anti-patterns

❌ **Gửi task mơ hồ cho Lead** → Lead sẽ đoán, output sai scope  
❌ **Dùng Peer để implement** → Peer không có delegation, toolset bị hạn chế  
❌ **Bỏ qua Supervisor cho task phức tạp** → Không có coordination, Lead làm trùng nhau  
❌ **Để Supervisor implement thay Lead** → Mất điểm isolation, khó debug  
❌ **Merge mà không có Peer review cho security code** → Risk cao  
