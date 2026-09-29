# Onboard một dự án đã chạy một thời gian (brownfield)

Khác biệt cốt lõi so với dự án mới: **repo không còn là sân trống**. Có lịch sử, có remote, có test đang đỏ, có quy ước riêng, có người khác đang làm. Room phải *hoà vào* repo đó, không được viết lại theo ý mình.

## Bước 0 — Điều kiện (chốt với Human TRƯỚC khi dispatch)

Phải hỏi và ghi vào brief, đừng tự suy:
1. **Chạy ở đâu?** — "mọi thứ chạy trong docker, không được chạy lệnh nào ngoài docker" là ràng buộc rất thường gặp. Nếu app đã chạy sẵn (dev mode), peer **không được** tự start server, càng không được chạy `npm`/`node` trên host. Lệnh hợp lệ: `docker exec` / `docker cp` vào container đang có; `docker compose up/down/restart` là **cấm** (đụng vào stack của Human).
2. **Container nào phục vụ app, port nội bộ nào, mount gì?** — kiểm bằng `docker inspect`: mount `src/` từ checkout chính nghĩa là **code trong worktree của peer KHÔNG phải thứ đang chạy**, và ghi vào `src/` đó sẽ hot-reload môi trường dev của Human (cấm tuyệt đối).
3. **Ghi dữ liệu test vào đâu?** — DB local trong docker thì phải được Human cho phép, test phải tag rồi tự dọn và chứng minh residual = 0.
4. **Cổng nghiệm thu thật là gì** — repo không có test suite thì build/behaviour, nhưng phải là lệnh chạy **trong docker**.

## Bước 1 — Supervisor chụp baseline (bắt buộc, trước khi dispatch)

```bash
bash scripts/onboard-repo.sh /path/to/repo            # chỉ đọc
bash scripts/onboard-repo.sh /path/to/repo --run-tests --out /tmp/baseline-<repo>.md
```

Script trả về đúng những thứ brief cần: branch/HEAD, **working tree có bẩn không**, quy tắc sẵn có trong repo (`AGENTS.md`, `CONTRIBUTING.md`, `CODEOWNERS`, `docs/WORKSPACE_PROTOCOL.md`), lệnh test/CI **thật** của dự án, hình dạng repo (thư mục nào nhiều file → chỗ chia write scope), và **kết quả suite hiện tại làm baseline**.

Ba con số phải chốt trước khi dispatch:
| Số | Lấy từ | Dùng làm gì |
|---|---|---|
| base commit | `git rev-parse HEAD` | mọi worktree branch ra từ đây |
| baseline test | `--run-tests` | **acceptance = không tệ hơn baseline** (đỏ sẵn vẫn được phép đỏ, nhưng không được đỏ thêm) |
| dirty entries | `git status --porcelain` | phải commit/stash trước, không thì peer branch ra từ HEAD mà mất phần chưa commit |

## Bước 2 — Bốn luật cho repo già

1. **Không merge thẳng vào `main` của anh.** Lead merge vào **branch tích hợp `room/<task>`** (branch ra từ HEAD). Anh xem diff rồi tự merge/push vào `main` thật. Lý do: `main` có thể được bảo vệ, có CI, có người khác đang pull.
2. **Quy tắc trong repo thắng mặc định của room.** `AGENTS.md` / `CONTRIBUTING.md` / CI config / style hiện có là hợp đồng — Peer phải theo, không được reformat file, không đổi style, không đổi lockfile/dependency khi chưa được duyệt.
3. **Acceptance = không hồi quy.** Test baseline đỏ 5 case thì sau khi xong vẫn đúng 5 case đỏ đó (liệt kê ra), không được "sửa luôn" nếu anh chưa cho phép. Tính năng mới thì thêm test mới, không sửa test cũ.
4. **Write scope là file/thư mục cụ thể trong repo thật**, không phải "module mới". Với repo già, một tính năng thường chạm nhiều file đang có → chia wave theo phụ thuộc, mỗi wave 1–3 peer, và **chỉ những file thật sự độc lập** mới cho chạy song song. Không tách giả cho đẹp.

## Bước 3 — Contract đọc từ code, không phải tự nghĩ ra

Lead phải **đọc code hiện có** rồi ghi `docs/CONTRACT.md` = bản mô tả interface *đang tồn tại* (chữ ký hàm, schema dữ liệu, mã lỗi, format file cũ) + ranh giới file từng peer. Với repo già, contract gần như luôn kèm:

- **tương thích ngược** (file/dữ liệu/API cũ phải còn đọc được, có test chứng minh);
- **migration** nếu đổi schema (đọc được định dạng cũ, không tự ghi đè dữ liệu người dùng);
- **điểm chạm đã biết** (module nào import module nào) để xếp thứ tự wave đúng.

## Bước 4 — Những thứ thường chặn ở repo già (phải nêu sớm)

Đây là các "blocker" điển hình, Lead phải báo Supervisor **trước khi** dispatch nếu thiếu — thay vì đoán:

- env/secrets, file `.env.local`, credentials để chạy test;
- fixture, database, service ngoài (docker compose, local server);
- test cần mạng/quyền đặc biệt hoặc chạy > vài phút;
- repo có submodule / LFS / generate code bằng script riêng;
- phần code sắp chạm đang có người khác sửa (nhánh dài hạn, PR đang mở).

## Mẫu câu cho anh (paste vào ghế Supervisor)

```
Dự án cũ: /path/to/repo
Đây là repo đã chạy thật: đừng viết lại, đừng đổi style, đừng đụng file ngoài phạm vi.
Mục tiêu: <outcome>
Phạm vi cho phép chạm: <thư mục/file>
Không được chạm: <migrations, CI, lockfile, docs công khai...>
Acceptance: <lệnh test thật> phải xanh không hồi quy (baseline: <n>/<m> pass)
Việc cấm: không push, không merge vào main — làm trên branch room/<task-slug>
```

## Khác biệt tóm tắt: xanh-field vs brownfield

| | Dự án mới | Dự án đã chạy |
|---|---|---|
| Base | commit rỗng + README hợp đồng | HEAD hiện tại, **có baseline test** |
| Merge vào | `main` (repo chưa ai dùng) | branch `room/<task>` → anh duyệt rồi mới vào `main` |
| Acceptance | feature chạy + test mới xanh | **không hồi quy** + test mới xanh |
| Contract | do Lead thiết kế | Lead **đọc từ code** rồi mới ghi |
| Rủi ro chính | scope creep | **phá thứ đang chạy** (schema, style, dependency) |
| Số peer song song | nhiều (module rời) | ít hơn, chia theo file thật sự độc lập |
