# Phiếu Phản Ánh — K4 Level 3A, Ngày 12

> **Bài làm cá nhân.** Trả lời bằng lời của chính bạn, dựa trên những gì bạn
> quan sát được khi chạy code — không sao chép đáp án của người khác.
>
> Cách trả lời: thay dòng giữ chỗ bằng câu trả lời của bạn.
> `grade.py` đếm số câu đã trả lời (15 điểm cho 10 câu).
>
> Họ và tên: Nguyễn Văn Chiến  Mã học viên: L3A202602926

---

### Câu 1 — Fail fast (CP1)

Trong `Settings`, `agent_api_key` không có giá trị mặc định nên app chết ngay
khi khởi động nếu thiếu biến môi trường. Hãy mô tả một tình huống cụ thể mà
việc "chết sớm" này cứu bạn, so với việc để mặc định `"changeme"`.

Tình huống của tôi: tôi deploy lên Render bằng `render.yaml`, và trong file đó tôi
quên khai báo `AGENT_API_KEY` trong khối `envVars`. Lúc này có hai cách xử lý:

- **Cách hiện tại (không có giá trị mặc định):** `Settings()` ném `ValidationError`
  ngay trong lúc uvicorn import `app.main`. Container start rồi chết ngay, Render
  đánh dấu deploy là **Failed** kèm log `Field required [type=missing]`. Tôi đọc
  log là biết ngay thiếu biến gì, sửa `render.yaml`, deploy lại — mất 2 phút.
- **Nếu có mặc định `"changeme"`:** app vẫn boot bình thường, `/health` trả 200,
  Render báo deploy **thành công**. Tôi sẽ tin là xong và đi khoe link. Nhưng mọi
  request `POST /ask` đều đi kèm header `X-API-Key: changeme`, và kẻ tấn công chỉ
  cần đoán ra chuỗi mặc định này là gọi được miễn phí. Tôi phải mở log từng dòng
  `ask_completed` mới phát hiện có lưu lượng lạ từ IP không rõ nguồn, lúc đó
  request đã đốt tiền rồi.

Tệ nhất là trường hợp lẫn giữa: môi trường staging tôi set đúng, production quên.
Với mặc định, app ở production vẫn chạy — tức là lỗi cấu hình *im lặng* chỉ lộ ra
dưới dạng hoá đơn tiền API. Fail fast đổi "lỗi im lặng lúc 3h sáng" thành "lỗi
to, ồn, xuất hiện ngay ở lần deploy đầu tiên". Ngoài ra ở đây còn một lý do kỹ
thuật: secret mặc định nằm sẵn trong code nên nó đã được commit lên Git — ai đọc
repo cũng có, nên coi như không còn bí mật nữa.

---

### Câu 2 — Log cho máy đọc (CP1)

Chạy service và gọi `/ask` vài lần. Dán một dòng log JSON bạn thu được, rồi
nêu **hai** việc bạn làm được với dòng log đó mà `print("đã trả lời xong")`
không làm được.

Đây là dòng log thật tôi thu được từ `docker compose logs agent` sau 3 lần gọi
`/ask` với `X-User-Id: sv01`:

```json
{"event": "ask_completed", "level": "info", "timestamp": "2026-09-28T08:24:34.078987+00:00", "user_id": "sv01", "tokens_in": 43, "tokens_out": 47, "cost_usd": 3.465e-05}
```

**Việc 1 — cộng dồn chi phí theo từng user mà không cần sửa code.** Mỗi dòng có
`cost_usd` và `user_id` ở đúng vị trí, nên trên Render tôi vào dashboard
"Logs → Query" gõ `json_extract(cost_usd)` là ra bảng xếp hạng ai tiêu nhiều
tiền nhất, không cần đụng vào app. Với `print("đã trả lời xong")` thì dòng log
đó không có con số nào để lấy — muốn biết user nào tốn tiền thì phải sửa code
để in ra, rồi deploy lại, rồi chờ có traffic.

**Việc 2 — cảnh báo tự động khi có dấu hiệu bất thường.** Vì `level` là một
*field* chứ không phải từ khoá nằm trong câu văn, tôi đặt được alert kiểu
"alert khi `level = "error"`" mà không sợ dính nhầm vào chuyện không liên quan
(hay gặp ở dạng `print`: tìm chuỗi "error" trong log sẽ khớp luôn cả câu "không
có error nào"). Thêm nữa `timestamp` ở chuẩn ISO-8601 UTC nên log từ nhiều
container, nhiều instance đặt cạnh nhau vẫn sắp đúng thứ tự thời gian.

Còn một điểm tôi thấy ngay khi so sánh: nếu dùng `print`, các dòng log của
FastAPI/uvicorn xen kẽ với dòng của tôi, người đọc phải tự đoán dòng nào là của
app. JSON một dòng thì grep được, lọc được, `jq` được, và quan trọng nhất là
**máy** đọc được chứ không chỉ mắt tôi.

---

### Câu 3 — Kích thước image (CP2)

Build cả hai phiên bản và ghi lại số đo thật:

```bash
docker build -f <Dockerfile-1-stage> -t agent:single .
docker build -t agent:multi .
docker images | grep agent
```

| Bản | Dung lượng |
|-----|-----------|
| 1 stage (bản đầu) | ... MB |
| Multi-stage | ... MB |

Giải thích: phần dung lượng chênh lệch đó là những gì?

Số đo thật của tôi (`docker inspect --format '{{.Size}}'`):

| Bản | Dung lượng |
|-----|-----------|
| 1 stage (bản đầu) | **288.8 MB** |
| Multi-stage | **258.5 MB** |

Chênh lệch **~30 MB**. Để biết 30 MB đó là gì chứ không phải đoán, tôi vào
trong từng image kiểm tra:

| Kiểm tra | 1 stage | Multi-stage |
|----------|---------|-------------|
| `du -sh /root/.cache/pip` | **17 MB** | không tồn tại |
| `which gcc g++ make` | không có | không có |
| `ls -d /build /usr/src/*` | không có | không có |
| `du -sh .../site-packages` | 77 MB | 77 MB |
| user chạy | `root` (uid 0) | `appuser` (uid 10001) |

Vậy phần chênh lệch nằm ở **cache pip bị giữ lại trong image**: bản 1 stage chạy
`pip install -r requirements.txt` không kèm `--no-cache-dir`, nên wheel/.tar.gz
đã tải và dùng xong vẫn nằm trong `/root/.cache/pip` (~17 MB) và bị đóng băng
vào layer vĩnh viễn — image đẩy lên registry và tải về mỗi lần deploy đều phải
kéo theo 17 MB vô ích. Bản multi-stage vứt stage `builder` đi nên cache đó không
lọt vào image cuối.

Điều đáng nói hơn 30 MB: hai image có **cùng bộ thư viện y hệt** (77 MB
site-packages) và cùng một base image. Nghĩa là multi-stage ở đây *không* làm
image nhỏ đi một cách kỳ diệu — phần lớn 258 MB là Python runtime (base
`python:3.11-slim` một mình đã 178 MB) cộng thư viện. Multi-stage thu được cải
thiện thật sự nằm ở chỗ khác mà tôi kiểm tra được: image cuối **không chứa
compiler, không chứa `/build`, không chứa `~/.cache/pip`**, và quan trọng nhất là
**không chạy bằng root** (uid 10001 thay vì 0). Với một service web chỉ cần
`uvicorn` + `redis` + `pydantic`, đó mới là phần thu hẹp bề mặt tấn công có
giá trị nhất, chứ không phải con số MB.

---

### Câu 4 — Thứ tự lệnh trong Dockerfile (CP2)

Sửa một ký tự trong `app/main.py` rồi build lại. Với Dockerfile của bạn, những
layer nào được dùng lại từ cache, layer nào phải chạy lại? Nếu bạn đặt
`COPY . .` lên trước `RUN pip install` thì kết quả khác thế nào?

Tôi thử bằng cách đổi đúng một chữ trong `app/main.py` (đổi `SERVICE_VERSION`
từ `"1.0.0"` thành `"1.0.1"`) rồi build lại image multi-stage của mình:

```
#6  CACHED     ← từ base image python:3.11-slim
#7  CACHED     ← ENV PYTHONDONTWRITEBYTECODE / PYTHONUNBUFFERED
#8  CACHED     ← WORKDIR /app
#9  CACHED     ← groupadd + useradd appuser
#10 CACHED     ← COPY --from=builder /install /usr/local   (cài thư viện)
#11 CACHED     ← COPY app
#12 DONE 0.0s ← COPY utils
#13 DONE 0.3s
```

Đo thời gian thật: **4.3 giây**.

Nguyên tắc Docker cache là mỗi `RUN`/`COPY`/`ADD` sinh một layer, và cache chỉ
được dùng lại khi **layer đó và tất cả layer trước nó đều không đổi**. `COPY`
cũng vậy — nó không chỉ so nội dung file, mà so cả *checksum của thư mục chứa
nó*. Vì vậy `COPY app` và `COPY utils` phải chạy lại (chúng ở **sau** `pip
install` trong Dockerfile của tôi), còn lớp `pip install` ở trước thì vẫn CACHED
vì nó không nằm trong điều kiện phụ thuộc của `COPY app`.

**Nếu đặt `COPY . .` lên trước `RUN pip install`:** tôi đã viết thử một
Dockerfile riêng để đo, và build lại lần nữa sau khi sửa `main.py`:

| Thứ tự | Thời gian build khi sửa 1 ký tự |
|--------|-------------------------------|
| `COPY requirements.txt` → `pip install` → `COPY app` (của tôi) | **4.3 s** |
| `COPY . .` → `pip install` (sai thứ tự) | **355.6 s** |

Chênh hơn 80 lần. Lý do: `COPY . .` đặt **toàn bộ thư mục làm việc** vào trước,
nên checksum của nó thay đổi mỗi khi bất kỳ file nào trong repo đổi — kể cả
khi bạn chỉ sửa một dòng Python. Docker buộc phải vô hiệu hoá cache của mọi
layer *phía sau* nó, mà `pip install` nằm ngay sau, nên **toàn bộ** thời gian cài
thư viện phải chạy lại từ đầu (~6 phút) dù không một byte nào của
`requirements.txt` thay đổi.

Cách tôi tránh: copy `requirements.txt` **riêng một dòng** và đặt nó *trước*
source code, rồi mới `COPY app`/`COPY utils` từng thư mục. Biến thành "sửa code
→ 4 giây" thay vì "sửa code → 6 phút". Đây cũng là lý do trong Dockerfile của tôi
không có `COPY . .`: ngoài chuyện cache, copy cả repo còn kéo theo `.git`,
`.venv`, `screenshots` và file `Dockerfile*` tạm vào image — thứ mà
`.dockerignore` phải chặn cho đỡ.

---

### Câu 5 — Vì sao không chạy bằng root (CP2)

Container mặc định chạy bằng root. Mô tả chuỗi sự kiện dẫn từ "một lỗ hổng
trong code Python của bạn" tới "kẻ tấn công có quyền cao trên máy host", và
lệnh `USER` cắt đứt chuỗi đó ở chỗ nào.

Chuỗi sự kiện, từng bước:

1. **Lỗ hổng ở tầng app.** Ví dụ trong bài này: `utils/mock_llm.py` nhận
   `question` từ request. Nếu ở chỗ nào đó sau này tôi nối chuỗi đó vào một lệnh
   hệ thống, hoặc có `pickle.loads` trên dữ liệu không tin cậy, thì kẻ tấn công
   kiểm soát được thứ chạy **bên trong** container.
2. **Code chạy với quyền của process.** Không có khái niệm user trong Python —
   process làm gì thì hệ điều hành cho phép hết. Container mặc định chạy
   `root` (uid 0), nên bước 2 là: **đọc/ghi mọi file trong container, cài đặt
   phần mềm, đổi cấu hình hệ thống**.
3. **Container "root" không phải root thật — nhưng đó là điểm yếu, không phải
   điểm mạnh.** Ở chế độ mặc định (không dùng user namespace remap), uid 0 trong
   container được ánh xạ thẳng thành uid 0 trên **host**. Nghĩa là lệnh
   `apt-get install` hay ghi vào `/etc/passwd` trong container là ghi vào chính
   filesystem của máy thật.
4. **Container escape hoặc lợi dụng cấu hình sai.** Kernel và Docker daemon là
   ranh giới, nhưng nó không hoàn hảo: lỗ hổng kernel, mount nhầm host socket,
   `privileged: true`, hoặc container có quyền ghi vào volume dùng chung với
   host. Bước 3 khiếu hơn khiếu; lỗi cấu hình của người vận hành thì lỗi vận
   hành rất phổ biến. Và **càng nhiều bề mặt tấn công bên trong container thì
   càng dễ đi tới bước 4.**

**Lệnh `USER` cắt chuỗi ở bước 2.** Khi tôi đặt `USER appuser` (uid 10001),
kẻ tấn công đã kiểm soát được code của tôi vẫn bị giới hạn bởi quyền của một
user thường. Tôi đã kiểm tra bằng `docker run --rm --entrypoint sh agent:multi -c "id -u"`
và nhận `10001`, không phải `0`. Cụ thể là họ không đọc được `/etc/shadow`, không
cài được package hệ thống, không đổi được user trong image, không ghi được vào
`/usr/local/lib/python3.11/site-packages` (file này thuộc root) — nên không thể
cài backdoor vào image rồi chờ lần deploy sau lây nhiễm.

Điểm quan trọng: `USER` là **giảm thiểu rủi ro theo chiều sâu** (defense in
depth), không phải vá lỗ hổng. Lỗ hổng ở bước 1 vẫn tồn tại và vẫn cho phép đọc
dữ liệu, đọc biến môi trường (gồm `AGENT_API_KEY`!) và gọi API nội bộ. Đó là lý
do tôi vẫn còn auth + rate limit + cost guard ở tầng app: nhiề lớp, mỗi lớp một
loại tấn công. Và vì container vẫn là "root" trên host nếu không remap, tôi
cũng tránh `privileged`, không mount Docker socket, và không mount volume
host nào vào container.

---

### Câu 6 — Cửa sổ trượt (CP3)

Rate limit của bạn dùng sliding window 60 giây. Nếu thay bằng cách đếm theo
phút đồng hồ (reset lúc giây 00), một người dùng có thể gửi tối đa bao nhiêu
request trong 2 giây liên tiếp khi hạn mức là 10/phút? Giải thích cách đạt được
con số đó.

**Đáp án: 20 request.**

Cách đạt: chọn thời điểm bất kỳ nằm sát ranh giới phút, rồi bắn một nửa hạn mức
về phía trước và một nửa về phía sau:

- Từ giây **58** đến giây **59** (tức 10:00:58 → 10:00:59, thuộc phút 10:00):
  bắn **10 request**. Phút 10:00 đã đủ 10/10, vẫn "đúng luật".
- Sang giây **00** (10:01:00): bộ đếm **reset về 0** vì bắt đầu phút mới. Bắn tiếp
  **10 request** ngay trong 10:01:00–10:01:01, phút 10:01 mới đạt 10/10.

Tổng cộng **20 request chỉ trong khoảng 2 giây** (10:00:58 → 10:01:01), gấp đôi
hạn mức vốn có, mà bộ đếm không lúc nào báo vượt.

Tệ hơn nữa nếu kẻ tấn công lặp lại mẹo ranh giới phút này liên tục: mỗi vòng
đều đẩy được 20 request/2 giây, tức **~600 request/phút** thay vì 10 — tỉ lệ
tăng 60 lần. Hạn mức 10/phút biến thành vô nghĩa.

Vì sao sliding window của tôi tránh được: `hit_count` làm
`ZREMRANGEBYSCORE key 0 now-60` trước rồi mới `ZCARD` — nghĩa là nó **đếm trong
60 giây gần nhất tính từ thời điểm hiện tại**, không phụ thuộc mốc phút. Ở giây
10:01:00, các request lúc 10:00:58–59 vẫn nằm trong cửa sổ (mới 1–2 giây trước)
nên vẫn bị tính; nếu đã bắn đủ 10 thì request thứ 11 nhận `429`. Tôi đã kiểm chứng
đúng hành vi này: gọi liên tiếp 14 lần với `RATE_LIMIT_PER_MINUTE=10` thì 10 lần
đầu `200` và từ lần 11 trở đi đều là `429` — không có lần nào "lọt" ở ranh giới
phút.

---

### Câu 7 — Rate limit và cost guard (CP3)

Hai cơ chế này khác nhau ở điểm nào? Cho một tình huống mà rate limit cho qua
nhưng cost guard phải chặn, và một tình huống ngược lại.

**Khác nhau về đơn vị đo.** Rate limit đo **số lượng request** trong cửa sổ thời
gian (10/phút) — nó bảo vệ *hạ tầng*, để một user không làm service quá tải hay
đập endpoint khác. Cost guard đo **tiền** theo tích luỹ trong tháng
(`MONTHLY_BUDGET_USD`) — nó bảo vệ *ví tiền*, để tổng chi phí gọi LLM không vượt
ngân sách. Một cái là hạn mức tức thời và tự xóa sau 60 giây; cái kia là tổng
dồn giữ nguyên suốt tháng.

**Rate limit cho qua nhưng cost guard chặn:** user bình thường, hỏi đều đặn 1
request/phút nên chưa bao giờ chạm 10/phút — rate limit cho qua thoải mái. Nhưng
mỗi câu hỏi của user đó là một bài luận dài khoảng 50.000 token, và chạy một
tháng là 20.000 câu như vậy. Tổng chi phí vượt `MONTHLY_BUDGET_USD` dù
"chưa request nào bị chặn". Tôi đã tái hiện đúng tình huống này bằng cách hạ
`MONTHLY_BUDGET_USD` xuống `0.00005` (bình thường là 10.0) rồi gọi `/ask` 3 lần
với cùng một `X-User-Id`: lần 0 và 1 trả `200` (chi phí lần lượt 2.355e-05 và
3.63e-05 USD), lần 2 trả **`402 {"detail":"monthly budget exceeded"}`** — và
đây là request thứ 3 trong cùng một phút, hoàn toàn không vướng rate limit.

**Ngược lại, cost guard cho qua nhưng rate limit chặn:** một script gọi liên
tục 200 request/phút với câu hỏi cực ngắn ("hi", 1–2 token). Tổng tiền của 200
câu đó rất nhỏ, nên cost guard vẫn còn ngân sách và cho qua. Nhưng 200
request/phút là một cú flood: nó chiếm worker của uvicorn, làm `/ask` của
người dùng thật phải chờ, và làm mất hiệu lực các endpoint khác trên cùng
server. Tôi đã tái hiện tình huống này với hạn mức 10/phút: 14 lần gọi liên
tiếp cho kết quả `200` × 10 rồi `429` × 4.

Vì sao phải có cả hai: chúng bảo vệ **hai tài nguyên khác nhau** nên không thay
thế được. Đặt cả hai cùng lúc (thứ tự trong `main.py` là
`limiter.check` → `guard.check` → mới gọi LLM) vì tiền chỉ mất ở đúng bước gọi
LLM — chặn sau khi đã gọi thì vừa mất tiền vừa vẫn phải trả lỗi cho user.

---

### Câu 8 — /health khác /ready (CP4)

Nếu gộp hai endpoint làm một và cho nó kiểm tra Redis, chuyện gì xảy ra với cụm
3 container khi Redis mất kết nối 30 giây? Trả lời theo đúng thứ tự sự kiện.

Giả sử `/health` kiểm tra Redis, cụm có 3 container, Redis mất kết nối 30 giây:

1. **Giây 0 — Redis ngừng trả lời.** Các lệnh ping từ cả 3 container bắt đầu
   timeout.
2. **Giây 0–5 — probe thất bại, `restart` được kích hoạt.** Kubernetes (hoặc
   liveness check của orchestrator) thấy `/health` trả lỗi liên tục quá ngưỡng
   `failureThreshold` → quyết định **container chết** → **kill và tạo lại nó**.
3. **Container mới sinh ra lại cũng cần Redis** để qua cùng cái probe đó — mà
   Redis vẫn chết. Probe tiếp tục đỏ. **Vòng lặp khởi động lại (crash loop).**
4. **Cả 3 container cùng restart cùng lúc**, mỗi vòng lặp cách nhau vài giây.
   Trong 30 giây đó, dịch vụ **hoàn toàn không phục vụ** — không phải chậm, mà
   là **0 request thành công**, dù ứng dụng của tôi vẫn chạy tốt và chỉ đơn
   giản là không đọc được lịch sử hội thoại.
5. **Giây 30 — Redis hồi phục.** Cả 3 container mới lần lượt khởi động lại và
   probe xanh. Nhưng đã mất 30 giây downtime **và** thêm một đợt nữa để chờ
   container lên, cộng với việc lịch sử hội thoại trong RAM các instance cũ bị
   mất.

Vấn đề cốt lõi: **liveness trả lời "có cần restart tôi không?"** — và câu trả
lời khi Redis chết là **không**, vì app của tôi hoàn toàn khỏe, chỉ là dependency
hỏng. Restart không sửa được Redis, nên chỉ tạo ra thêm nhiễu. Tôi đã viết
`/health` cố ý **không** chạm vào Redis: nó chỉ hỏi "process còn sống không?" và
trả 200. Còn `/ready` mới là câu hỏi "nên gửi traffic vào đây không?" — nó gọi
`store.ping()` trong try/except và trả `503 {"status":"not ready","redis":false}`
khi Redis không đáp.

Với hai endpoint tách bạch, cùng sự cố đó sẽ diễn ra rất khác: `/health` vẫn
200 nên **không container nào bị restart**; chỉ `/ready` chuyển sang 503 nên
**load balancer rút cả 3 container ra khỏi vòng xoay** và dừng gửi request mới
tới. Khi Redis hồi phục, `/ready` xanh và traffic vào lại. Nếu lúc đó có
cân bằng tải phía trên, nó thậm chí còn có thể **định tuyến sang dịch vụ khác**
thay vì trả lỗi cho user. Tôi cũng xử lý trường hợp ngược lại (đang tắt dần) ở
cả hai endpoint: `/health` trả 503 `{"status":"shutting_down"}` để orchestrator
biết đây là chủ đích, không phải crash.

---

### Câu 9 — Stateless (CP4)

Chạy `docker compose up --scale agent=3` rồi gọi `/ask` nhiều lần với cùng một
`X-User-Id`. Quan sát `history_length` trong response. Nếu lịch sử được lưu
trong một dict Python thay vì Redis, bạn sẽ thấy con số đó thay đổi thế nào?

Tôi chạy `docker compose up -d --scale agent=3` rồi gọi `/ask` 6 lần với cùng
`X-User-Id: scale-test` qua nginx:

```
call 1 => history_length=0    call 4 => history_length=6
call 2 => history_length=2    call 5 => history_length=8
call 3 => history_length=4    call 6 => history_length=10
```

Điểm cần kiểm chứng là **6 lần này có thật sự rơi vào 3 container khác nhau
không** — nếu tất cả cùng đi vào một container thì bài toán chưa xuất hiện. Tôi
đếm log `ask_completed` trên từng container: `agent-1: 2`, `agent-2: 2`,
`agent-3: 2`. Tức là round-robin phân bổ đều, và `history_length` **vẫn tăng
đều 0→2→4→6→8→10** xuyên suốt 3 tiến trình Python khác nhau. Đó chính là
stateless đúng nghĩa: process nào xử lý không quan trọng, vì **không process nào
giữ state**.

Cộng thêm `cost_usd` cũng cộng dồn đều, vì key tính tiền
(`cost:scale-test:2026-09`) và key rate limit (`ratelimit:scale-test`) đều nằm
trong Redis chứ không nằm trong RAM.

**Nếu lịch sử nằm trong dict Python thay vì Redis**, con số đó sẽ **nhảy về 0
rồi đếm lại từ đầu** mỗi khi request rơi sang container khác — mà nó sẽ rơi
liên tục vì load balancer không có khái niệm "user này đang ở container kia".
Cụ thể với kịch bản round-robin trên, tôi dự đoán `history_length` sẽ là
`0, 0, 2, 2, 4, 4` thay vì `0, 2, 4, 6, 8, 10`: cứ hai request liên tiếp rơi
vào cùng một container thì nó thấy lịch sử của lần trước, rồi lại về 0 ở
container kế. Trải nghiệm người dùng là con agent **bị mất trí nhớ cứ hai câu**,
đúng cái lỗi mà tài liệu CP4 cảnh báo.

Tệ hơn nữa là khi container bị restart (deploy bản mới, crash, autoscaler thu
bớt instance) — toàn bộ dict biến mất cùng tiến trình, mất sạch, và việc
mở rộng ngang lúc đó lại **không thay thế được** vì người dùng phải dán lại
lịch sử vào từng instance. Đó là lý do `ConversationStore` ghi vào Redis List
(`RPUSH` + `LTRIM` giới hạn 20 message + `EXPIRE` 7 ngày): state nằm ngoài
process, nên thêm bao nhiêu instance cũng được, và mất một instance không mất
dữ liệu.

Cùng lý do đó, tôi **không** deploy `fakeredis` (`REDIS_URL=fake://`) lên cloud dù
điều đó tiện cho lúc học — vì `fakeredis` vẫn là state trong RAM của process, tức
là đúng cái trạng thái mà CP4 nói phải loại bỏ.

---

### Câu 10 — Deploy thật (CP5)

Ghi lại **một** lỗi bạn gặp khi deploy lên cloud (build fail, health check
timeout, sai REDIS_URL, app không đọc `$PORT`...): thông báo lỗi là gì, bạn
tìm ra nguyên nhân bằng cách nào, và sửa ra sao?

Lỗi tôi gặp là **lỗi local trong compose, đúng loại lỗi mà nếu không chạy thật
thì sẽ chỉ phát hiện khi đã lên cloud**: cấu hình scale của mình không chạy
được với 3 container.

**Thông báo lỗi:**

```
Error response from daemon: failed to set up container networking:
driver failed programming external connectivity on endpoint
...-agent-3 (...): Bind for 0.0.0.0:8000 failed: port is already allocated
```

Container `agent-1` lên được rồi `agent-3` báo lỗi. Song song, `nginx` cũng đang
lặp vòng `Restarting (1)` với:

```
nginx: [emerg] 1#1: "events" directive is not allowed here
in /etc/nginx/conf.d/default.conf:8
```

**Tìm ra nguyên nhân bằng cách nào:** tôi đọc log thay vì đoán. Với nginx, dòng lỗi
chỉ rõ file và dòng (`conf.d/default.conf:8`) — vị trí đó đúng là khối `events`
trong `nginx/nginx.conf` của tôi, nên nguyên nhân là **mount nhầm chỗ**: tôi gắn
file vào `/etc/nginx/conf.d/default.conf`, nhưng thư mục `conf.d` chỉ nhận các
khối `server` *lồng trong* `http`; khối `events` chỉ được phép ở cấp ngoài cùng
nên phải mount vào `/etc/nginx/nginx.conf`.

Với lỗi port, tôi hiểu ngay vì đã học quy tắc "mỗi container publish ra host
một cổng cố định thì chỉ chạy được một bản": `ports: - "8000:8000"` của tôi khiến
cả 3 container đều đòi chiếm cùng cổng 8000 trên host — mà host chỉ có một cổng
8000. Cách xác nhận là nhìn `docker compose ps` và thấy `agent-1` healthy,
`agent-3` không có, còn `nginx` restart.

**Sửa ra sao:** hai thay đổi, cùng một ý tưởng là *tách cổng vào từ host ra khỏi
các container worker*:

1. Đổi `ports: ["8000:8000"]` của `agent` thành `expose: ["8000"]`. `expose` chỉ
   mở cổng **trong mạng nội bộ compose**, đủ cho nginx và các agent cùng thấy
   nhau mà **không giành cổng host** — scale bao nhiêu bản cũng được. Chỉ `nginx`
   mới `ports: ["8000:80"]`, tức host có đúng một cổng vào.
2. Mount `nginx.conf` vào `/etc/nginx/nginx.conf` thay vì `conf.d/default.conf`.

Sau khi sửa, `--scale agent=3` lên cả 3 container đều `healthy`, nginx `Started`,
và test Câu 9 ở trên (6 lượt, round-robin 2/2/2, `history_length` tăng đều) chạy
trên chính stack này.

**Bài học tôi rút ra, và cũng là lý do tôi ghi lại lỗi này:** cả hai lỗi đều
không liên quan gì đến code Python — chúng nằm ở tầng cấu hình hạ tầng, nơi
`pytest` không chạm tới. `tests/test_cp2.py` chỉ parse YAML và kiểm tra có
service `agent`, có `healthcheck`, `REDIS_URL` trỏ đúng... nên nó **xanh** trong
khi `docker compose up` thì vẫn nổ. Cùng một stack đó, đẩy lên cloud với
cổng do platform cấp sẽ sinh ra biến thể khác của chính lỗi này (ví dụ app
hardcode 8000 trong khi Render cấp cổng khác → health check timeout). Đây là
lý do tôi cần chạy stack thật thay vì chỉ tin test: test xanh là điều kiện cần,
không phải điều kiện đủ.

