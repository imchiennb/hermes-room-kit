# Prompt Templates

Copy-paste trực tiếp vào Paseo. Thay nội dung trong `[ ]`.

---

## SUPERVISOR — Task phức tạp

```
Task: [mô tả ngắn gọn mục tiêu]

Context:
- Repo: [đường dẫn]
- Branch hiện tại: [branch]
- Liên quan: [files/modules chính]

Constraint:
- [ràng buộc 1, ví dụ: không break API cũ]
- [ràng buộc 2, ví dụ: phải pass CI]

Definition of done:
- [tiêu chí 1]
- [tiêu chí 2]

Human approval cần cho: [ví dụ: merge vào main, deploy]
```

---

## SUPERVISOR — Bug điều tra nhiều hướng

```
Bug: [mô tả triệu chứng]

Reproduce:
[steps hoặc command để reproduce]

Error:
[paste error/stacktrace]

Đã thử:
- [thứ đã thử 1]
- [thứ đã thử 2]

Nghi ngờ:
- [hướng 1]
- [hướng 2]

Yêu cầu: Điều tra song song các hướng, tổng hợp root cause, đề xuất fix.
```

---

## LEAD — Task kỹ thuật bounded

```
Task: [mô tả cụ thể]

Files cần sửa:
- [file:line nếu biết]

Constraint:
- [ví dụ: chỉ sửa trong module X, không thêm dependency mới]

Test:
- [command chạy test, ví dụ: pytest tests/auth/]
- Phải pass trước khi return candidate

Return:
- Candidate commit hash + test output
- Hoặc: BLOCK [mô tả blocker cụ thể]
```

---

## LEAD — Fix bug cụ thể

```
Bug: [tên/mô tả]
File: [path:line]
Error: [paste error]

Reproduce: [command]

Fix và chạy: [test command]
Return candidate khi test pass.
```

---

## LEAD — Refactor

```
Refactor: [module/file]
Mục tiêu: [ví dụ: tách God class thành 3 class nhỏ hơn]

Giữ nguyên:
- Public API (các hàm/class exported)
- Behavior hiện tại

Được phép:
- Đổi internal structure
- Thêm tests mới

Test: [command] phải pass.
Nếu uncertain về approach → gọi Peer review trước khi implement.
```

---

## PEER — Code review

```
Review: [file hoặc commit hash]

Context:
[mô tả ngắn: đây là module gì, làm gì]

Check đặc biệt:
- [ví dụ: edge case khi token expired]
- [ví dụ: SQL injection ở input X]
- [ví dụ: race condition trong concurrent requests]

Return:
ACCEPT [lý do ngắn] 
-- hoặc --
BLOCK [file:line] [vấn đề cụ thể] [fix cần làm]
```

---

## PEER — Security review

```
Security review: [file/module]

Code làm gì: [mô tả ngắn]

Check:
- Auth/authz logic
- Input validation tại trust boundaries
- Secret/key handling
- SQL/command injection
- Token/session management

Return ACCEPT hoặc BLOCK với evidence cụ thể.
```

---

## PEER — PR review trước merge

```
PR review: [branch hoặc diff]

Context: [mô tả PR làm gì]

Diff: [paste diff hoặc chỉ path file thay đổi]

Check:
- Logic correctness
- Error handling
- Breaking changes với API hiện tại
- Test coverage đủ chưa

Return ACCEPT hoặc BLOCK.
```

---

## Handoff: Supervisor gửi output của Lead sang Peer

```
[Paste output/candidate từ Lead]

---
Peer: Review candidate trên.
Context: [mô tả task gốc]
Tập trung: [điểm cần check kỹ]
Return ACCEPT hoặc BLOCK.
```
