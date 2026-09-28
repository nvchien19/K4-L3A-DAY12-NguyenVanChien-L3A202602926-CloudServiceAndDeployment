# ═══════════════════════════════════════════════════════════════════
# CP2 — Containerization (production-ready)
#
# Multi-stage: stage `builder` biên dịch rồi bị vứt đi, chỉ stage `runtime`
# mới trở thành image → nhẹ hơn và không mang theo compiler.
# Thứ tự lệnh: COPY requirements.txt → pip install → COPY code, để Docker
# cache được phần cài thư viện khi code thay đổi.
# Chạy bằng user thường (không phải root), có HEALTHCHECK, đọc $PORT.
#
# Kiểm tra:  pytest tests/test_cp2.py -v
# Build thử: docker build -t day12-agent:prod .
#            docker images day12-agent:prod     # xem dung lượng
# ═══════════════════════════════════════════════════════════════════

# ── Stage 1: builder ─────────────────────────────────────────
# Ở đây được phép cài compiler vì nó không đi vào image cuối.
FROM python:3.11-slim AS builder

ENV PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /build

# requirements.txt copy RIÊNG một dòng và đứng TRƯỚC source code:
# sửa code không làm mất cache của lớp cài thư viện.
COPY requirements.txt ./
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt


# ── Stage 2: runtime ─────────────────────────────────────────
# Chỉ base slim + kết quả cài đặt từ builder: không compiler, không pip cache.
FROM python:3.11-slim AS runtime

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

# Tạo user thường. Container chạy root nghĩa là lỗ hổng trong app cũng là
# root trên host.
RUN groupadd --gid 10001 appgroup \
    && useradd --create-home --uid 10001 --gid 10001 appuser

COPY --from=builder /install /usr/local

# Chỉ copy thứ image thật sự cần, không copy cả repo.
COPY --chown=appuser:appgroup app ./app
COPY --chown=appuser:appgroup utils ./utils

USER appuser

EXPOSE 8000

# Docker tự gọi endpoint này để biết container còn phục vụ được không.
# Không gửi API key: /health cố tình không yêu cầu xác thực.
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/health', timeout=4).read()" || exit 1

# Cloud tự gán PORT; ${PORT:-8000} để chạy được cả ở máy lẫn trên cloud.
# 0.0.0.0 chứ không phải 127.0.0.1 — bind localhost thì ngoài container gọi
# không vào được.
CMD ["sh", "-c", "exec uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000}"]
