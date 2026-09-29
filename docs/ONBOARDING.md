# Onboarding a project — new (greenfield) or long-running (brownfield)

Room đã dựng xong (`bash verify.sh` xanh) thì việc còn lại là **đưa một dự án vào room**. Không cần cài thêm gì; không phân biệt dự án mới hay cũ ở bước cài — chỉ khác ở luật giao việc.

## Bước 0 — Chốt với Human (đừng tự suy)

Bốn câu, trả lời trước khi dispatch:

1. **Môi trường chạy** — mọi thứ chạy trong Docker? App đã chạy sẵn (container nào, port nội bộ nào)? Có được chạy lệnh trên host không?
   Kinh nghiệm thật: một dự án quy định "mọi thứ trong docker", peer lại khởi động service **trên host** → cả wave phải brief lại. Nếu app đã chạy dev mode trong container thì peer **không được** tự start server; lệnh hợp lệ là `docker exec` / `docker cp` vào container đang có, còn `docker compose up/down/restart` là **cấm**.
   Kiểm tra mount của container trước: nếu container mount `src/` từ checkout chính thì (a) code trong worktree của peer **không phải thứ đang chạy**, và (b) ghi vào `src/` đó sẽ **hot-reload môi trường dev của Human**.
2. **Dữ liệu test** — được ghi vào DB nào? Peer phải tag dữ liệu, tự dọn, và chứng minh residual = 0.
3. **Acceptance chính thức** — lệnh nào là cổng nghiệm thu, chạy trong môi trường đã chốt.
4. **Ai push/merge** — chỉ Human. Room không push bao giờ; dự án cũ thì không merge vào nhánh chính.

## Bước 1 — Một lệnh, dùng cho cả hai loại dự án

```bash
bash scripts/onboard-project.sh /path/to/project --run-tests
```

Nó **tự phân loại** (và in lý do, không im lặng): `new` nếu chưa có git/không remote/ít commit/lịch sử mới; `existing` nếu có remote, ≥5 commit, lịch sử ≥7 ngày, hoặc có CI. Muốn ép thì `--mode new|existing`.

Sinh ra 2 file trong `baselines/`:
- `baseline-<project>-<date>.md` — facts máy đọc được: git state, lệnh test thật, kết quả baseline, hình dạng repo, CI, quy tắc có sẵn, chỗ có thể chia write scope.
- `brief-<project>-<date>.md` — **brief dán thẳng vào ghế Supervisor**, kèm 4 điều phải chốt và luật riêng cho từng loại dự án.

Chỉ đọc, không sửa gì trong repo. Cần thêm chi tiết git thì dùng trực tiếp `scripts/onboard-repo.sh`.

## Bước 2 — Dán brief vào Supervisor

Mở `brief-*.md`, trả lời 4 mục ở "phải chốt", rồi dán khối `text` vào ghế Supervisor. Mẫu gọn:

```
Dự án: /path/to/project
Loại: existing
Base commit: <sha> (nhánh develop)
Baseline: baselines/baseline-<project>-<date>.md
Mục tiêu: <outcome, 1–3 câu>
Phạm vi được chạm: <thư mục/file>     Không được chạm: <migrations, CI, lockfile, .env>
Acceptance: <lệnh test thật, chạy trong môi trường đã chốt>
Việc cấm: không push; không tự start server; không chạy lệnh ngoài môi trường đã chốt
```

## Bước 3 — Luật khác nhau giữa hai loại

| | **Dự án mới** | **Dự án đã chạy** |
|---|---|---|
| Hợp đồng sản phẩm | Supervisor viết README (mục tiêu, phạm vi, acceptance, ràng buộc) rồi commit base | README đã có thể đã tồn tại — Supervisor **đối chiếu và bổ sung acceptance**, không viết lại lịch sử |
| Contract nội bộ | Lead tự thiết kế (`docs/CONTRACT.md`) | Lead **đọc code rồi mới ghi** contract đang tồn tại + tương thích ngược/migration |
| Base cho worktree | commit base đầu tiên | `HEAD` hiện tại (tree phải sạch: commit/stash trước) |
| Acceptance | suite xanh + test e2e mới + smoke thật | **không hồi quy**: baseline đỏ bao nhiêu vẫn đúng bấy nhiêu; feature mới thêm test mới, không sửa test cũ |
| Merge vào | nhánh chính của repo (repo chưa ai dùng) | nhánh tích hợp `room/<task-slug>`; Human tự merge/push vào nhánh thật |
| Số peer song song | nhiều (module rời nhau) | ít hơn, chia theo file thật sự độc lập; không tách giả |
| Rủi ro chính | scope creep | **phá thứ đang chạy**: schema, style, dependency, môi trường dev |
| Việc phải nêu sớm | — | env/secrets để chạy test, fixture/DB/service ngoài, test chậm/cần mạng, submodule/code generate, vùng code có người khác đang sửa |

## Bước 4 — Khi loop đóng, Supervisor kiểm chứng (không nhận lời kể)

```bash
cd <project>
git log --graph --oneline -15                 # thứ tự merge có đúng phụ thuộc
git show --stat <candidate>                   # diff có đúng scope
git worktree list                             # mỗi peer 1 worktree
<lệnh acceptance>                             # tự chạy, không tin "test xanh"
```
Cộng thêm: đối chiếu `[createdAt, updatedAt]` của từng agent qua `get_agent_status` để chứng minh wave chạy song song thật, và kiểm `git diff <base>..HEAD -- <vùng cấm>` = rỗng.

Báo cáo cho Human: `scope | peer id | candidate | số vòng review | test trên main | verdict` + bằng chứng thô + rủi ro còn lại + **việc cần Human chốt** (hoặc "không có").

## Bước 5 — Những gì luôn thuộc về Human

Push, merge vào nhánh thật, chạy script trên DB thật, đánh index prod, xoá dữ liệu, đổi scope/hợp đồng, thêm dependency. Loop tự chạy phần còn lại; chỉ escalate khi bế tắc thật hoặc chạm các việc trên.

## Ví dụ đã chạy thật (đã ẩn danh)

- **Greenfield** (một CLI Python nhỏ): 4 scope (model/storage/service/cli) — 3 wave, tất cả ACCEPT, ~200 test xanh, smoke test CLI thật.
- **Brownfield** (một service NestJS chạy trong docker, **không có test suite**): baseline chỉ có `npm run build`; phát hiện `npm run lint` chứa `--fix` (sẽ ghi lại hàng trăm file) và `.prettierrc` CRLF làm hàng chục nghìn lỗi lint → lint bị loại khỏi cổng nghiệm thu; task chứng minh chạy 2 peer song song ~20 phút, verdict PROVEN kèm frame socket thô, **không đụng code sản phẩm**.
- **Bài học đắt nhất**: peer khởi động service **trên host** trong khi dự án chỉ chạy trong docker → cả wave phải brief lại. Vì vậy Bước 0 ở trên là bắt buộc.
