# Áp room vào một dự án khác

Không cần cài gì thêm — room đã dựng xong rồi (`bash verify.sh` xanh). Việc còn lại là **đưa dự án vào room**.
Toàn bộ chuẩn mực (topology, naming, dispatch, review loop) nằm trong skill `paseo-room-supervisor` của ghế Supervisor — mình đọc nó mỗi lần chạy.

## Bước 0 — Điều kiện

- Paseo Desktop đang chạy (daemon ở `127.0.0.1:6767`).
- Dự án là **git repo** (chưa có thì `git init` + commit base trước).
- Biết rõ **base commit** và **trạng thái test hiện tại** của repo — Lead sẽ cần con số này.

## Bước 1 — Anh nói mục tiêu với Supervisor

Chỉ cần paste vào ghế Supervisor (chỗ mình ngồi):

```
Dự án: <đường dẫn repo tuyệt đối>
Mục tiêu: <1–3 câu, outcome chứ không phải cách làm>
Ràng buộc: <ví dụ: không đổi API công khai, stdlib only, không đụng docs/...>
Điều kiện nghiệm thu: <lệnh test + hành vi phải quan sát được>
Việc cấm: <ví dụ: không push, không sửa file cấu hình chung>
```

Không cần dặn thêm gì về cách chia việc — đó là phần của Supervisor/Lead.

## Bước 2 — Supervisor chốt hợp đồng sản phẩm

Supervisor (mình) làm đúng 3 việc, **không tự code**:
1. Viết/đối chiếu `README.md` của repo: mục tiêu, phạm vi, acceptance (lệnh + hành vi), ràng buộc, ngoài phạm vi; commit base.
2. Tạo Paseo workspace cho đường dẫn repo, đặt tên `<repo> — <task ngắn>` (không tự chế hậu tố kiểu `(room demo 2)`).
3. Tạo ghế Lead **theo domain** (`Lead Backend — <project>`, `Lead Frontend — …`, `Lead Architecture — …`; nhiều Lead nếu task trải nhiều domain) bằng provider `hermes-lead`, mode `dont_ask`, kèm brief theo mẫu trong `skills/supervisor/autonomous-ai-agents/paseo-room-supervisor/references/briefs.md`.

## Bước 3 — Lead chạy vòng việc

Lead tự làm: đọc repo → chốt `docs/CONTRACT.md` (interface, schema, ranh giới file từng peer) → chia **wave** theo thứ tự phụ thuộc → tạo peer (provider `hermes-peer`, mỗi peer 1 worktree/branch, **cả wave trong một lượt**) → **review artifact từng candidate** (`git show`), trả bài về đúng peer nếu cần → lặp tới khi sạch → merge `--no-ff` → chạy full suite + smoke test thật → báo cáo.

## Bước 4 — Supervisor giám sát + kiểm chứng

Mình không nhận lời kể. Trước khi báo anh, mình chạy lại:

```bash
cd <repo>
git log --graph --oneline -15                      # thứ tự merge có đúng phụ thuộc
git log --format='%h %cI %s' <candidate>           # đối chiếu hash Lead báo
git show --stat <candidate>                        # diff có đúng scope không
git worktree list                                  # mỗi peer 1 worktree
<lệnh test trong README>                           # tự chạy acceptance
# và đo song song thật: khoảng [createdAt, updatedAt] của từng agent phải giao nhau
```
Rồi mới trả anh bảng: `scope | peer | candidate | số vòng review | test trên main | verdict` + rủi ro + việc cần anh chốt.

## Bước 5 — Anh chỉ bị gọi khi cần

Loop tự chạy. Anh chỉ nhận câu hỏi khi: **bế tắc thật** (thiếu quyền/dependency), hoặc **việc vượt quyền** (push/merge remote, xoá dữ liệu, đổi scope/hợp đồng, thêm dependency). Anh hỏi tiến độ bất cứ lúc nào → mình trả lời từ state thật (git + agent status), không đoán.

---

## Checklist dựng dự án mới (bản ngắn)

| # | Việc | Ai |
|---|---|---|
| 1 | Repo + base commit + trạng thái test | Anh |
| 2 | README = hợp đồng sản phẩm (acceptance rõ) | Supervisor |
| 3 | Paseo workspace + ghế Lead theo domain | Supervisor |
| 4 | `docs/CONTRACT.md` + chia wave | Lead |
| 5 | Peer theo worktree, cả wave một lượt | Lead |
| 6 | Review loop tới khi sạch + merge + smoke test | Lead |
| 7 | Verify độc lập (git, test, timestamp chồng lấn) | Supervisor |
| 8 | Duyệt push/merge remote | Anh |

## Mẹo để vòng chạy đúng ngay từ đầu

- **Task phải đủ lớn**: cần ≥2 write scope độc lập thì mới có song song thật và review loop có ý nghĩa. Task 1 file thì 1 Lead làm là đúng, đừng tách giả.
- **File dùng chung** (`README.md`, `cli.py`, `__main__.py`, contract) là single-writer → xếp wave sau.
- **Greenfield**: peer chỉ được `git add` file thuộc scope của mình, phần import chưa tồn tại thì tạo stub tạm (untracked).
- Khi Lead báo "song song" mà không có timestamp chồng lấn → coi như chưa đạt.
