# -- Build stage --
FROM python:3.12-slim AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc g++ libxml2-dev libxslt-dev && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY . .
RUN pip install --no-cache-dir ".[ai]"

# Pre-download SEC submissions dataset so edgar_screen works at startup
ENV EDGAR_IDENTITY="Civala inquiry@civala.com"
RUN python -c "from edgar.storage._local import download_submissions; download_submissions()"

# -- Runtime stage --
FROM python:3.12-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    libxml2 libxslt1.1 curl && \
    rm -rf /var/lib/apt/lists/*

COPY --from=builder /usr/local/lib/python3.12/site-packages /usr/local/lib/python3.12/site-packages
COPY --from=builder /usr/local/bin/edgartools-mcp /usr/local/bin/edgartools-mcp
COPY --from=builder /root/.edgar /root/.edgar

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
    CMD curl -f http://localhost:8000/health || exit 1

CMD ["edgartools-mcp", "--transport", "streamable-http", "--host", "0.0.0.0", "--port", "8000"]
