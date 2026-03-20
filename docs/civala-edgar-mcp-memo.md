# EdgarTools MCP Server — Civala Deployment Memo

**To:** Chris
**From:** Jordan
**Date:** 2026-03-20
**Re:** EdgarTools MCP deployment status on Dokploy

---

## Summary

We've deployed the EdgarTools MCP server to `edgar.civala.ai` on our Dokploy cluster. 10 of 13 tools are working. The remaining 3 (industry screening, peer comparison by industry, fund keyword search) require a bulk SEC dataset that needs more RAM to process than our container allows. There's a clear fix — details below.

## What's Working

| Tool | Status | Use Case |
|------|--------|----------|
| edgar_company | Working | Company profiles, financials, filings |
| edgar_filing | Working | Examine specific filings by accession number/URL |
| edgar_read | Working | Extract 10-K/10-Q sections (risk factors, MD&A, etc.) |
| edgar_search | Working | Find filings by company and form type |
| edgar_text_search | Working | Full-text search across all SEC filings |
| edgar_monitor | Working | Real-time SEC filing feed |
| edgar_compare (by ticker) | Working | Side-by-side financial comparison |
| edgar_ownership | Working | Insider transactions (Form 4) |
| edgar_notes | Working | Financial statement note drill-down |
| edgar_proxy | Working | Executive compensation (DEF 14A) |
| edgar_fund (by ticker) | Working | Fund lookup by ticker |
| edgar_trends | Working | Financial time series |

## What's Not Working

| Tool | Issue |
|------|-------|
| edgar_screen | Returns empty — needs company dataset |
| edgar_compare (industry mode) | Same root cause |
| edgar_fund (keyword search) | Same root cause |

## Root Cause

These 3 tools depend on a "company dataset" built by processing 964K JSON files from SEC's bulk submissions download (500MB compressed, 5GB extracted). The processing step loads all files into memory to build a pandas DataFrame, then saves it as a ~20MB parquet file. This one-time build requires **12-16GB RAM** due to:

- Python ZipFile central directory for 964K entries (~300MB)
- 964K parsed JSON dicts accumulated in a Python list (~640MB)
- PyArrow table construction (temporarily doubles the data)
- Docker overlay2 page cache accounting for 964K small files
- OS/Docker daemon overhead on the shared 16GB VM

Our container OOM-kills at ~34% with an 8GB memory limit on the 16GB Azure VM (Standard_D4s_v4).

This is not documented anywhere in edgartools — the library assumes a data science workstation with 16-32GB RAM. No GitHub issues exist for this because nobody has tried running it in a memory-constrained container before.

## Recommended Fix

**Pre-build the parquet file during Docker image build**, not at runtime. The dataset builder already outputs a `companies.pq` file (~20MB). We can:

1. Build the parquet on a machine with enough RAM (our local machines, or a temporary larger Azure VM)
2. Include only the 20MB parquet in the Docker image — not the 5GB of raw JSON files
3. Remove the volume mount entirely

This gives us instant startup, a small image, and no runtime memory spike. The parquet file would need rebuilding periodically (monthly is fine) as new companies file with the SEC.

**Alternative:** Upgrade the VM to Standard_D4s_v5 (same cost) or give the container 16GB and accept the one-time processing on first deploy.

## Security Audit

EdgarTools passed our security audit for Civala use:

- **MIT license** — no GPL/AGPL restrictions
- **Zero telemetry** — no phone-home, no analytics
- **Read-only architecture** — only pulls from public SEC APIs
- **No credentials in code** — identity via EDGAR_IDENTITY env var
- **SSL verification enabled by default** with system cert support
- **All dependencies permissive** (MIT, BSD, Apache 2.0)

## Infrastructure

- **URL:** https://edgar.civala.ai/mcp
- **Health check:** https://edgar.civala.ai/health
- **VM:** civala-ai-vm-01 (Standard_D4s_v4, 4 vCPU, 16GB RAM, East US)
- **Container image:** mcps-edgar-vgh3ph
- **Identity:** `Civala inquiry@civala.com`
- **Volume:** edgartools-data mounted at /root/.edgar (contains raw submissions data, can be removed after parquet fix)

## Changes Made to EdgarTools

3 commits pushed to `sapientsai/edgartools`:

1. **Dockerfile + health endpoint** — containerized MCP server with /health route for Dokploy monitoring
2. **outputSchema fix** — tools were declaring output schemas but returning text content, causing all tool calls to fail with schema validation errors
3. **Entrypoint for data download** — auto-downloads submissions data on first boot (working, but processing step OOMs)

## Next Steps

1. Implement parquet pre-build approach (1-2 hours of work)
2. Rebuild and redeploy — all 13 tools should work
3. Remove volume mount from Dokploy config
4. Set up monthly image rebuild to refresh SEC company data
