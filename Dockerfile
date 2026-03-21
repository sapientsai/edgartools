# -- Build stage --
FROM python:3.12-slim AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc g++ libxml2-dev libxslt-dev && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY . .
RUN pip install --no-cache-dir ".[ai]"

# Build company dataset parquet from SEC submissions data
# Downloads ~500MB, processes 964K JSON files, outputs ~14MB parquet
ENV EDGAR_IDENTITY="EdgarTools MCP Build edgartools@civala.com"
RUN python -c "\
from edgar.storage._local import download_submissions; \
download_submissions(); \
from edgar.reference.company_dataset import get_company_dataset; \
ds = get_company_dataset(rebuild=True); \
print(f'Company dataset built: {len(ds)} rows')"

# -- Runtime stage --
FROM python:3.12-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    libxml2 libxslt1.1 curl && \
    rm -rf /var/lib/apt/lists/*

COPY --from=builder /usr/local/lib/python3.12/site-packages /usr/local/lib/python3.12/site-packages
COPY --from=builder /usr/local/bin/edgartools-mcp /usr/local/bin/edgartools-mcp

# Only copy the 14MB parquet — not the 5GB raw submissions
COPY --from=builder /root/.edgar/companies.pq /root/.edgar/companies.pq

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD curl -f http://localhost:8000/health || exit 1

CMD ["edgartools-mcp", "--transport", "streamable-http", "--host", "0.0.0.0", "--port", "8000"]
