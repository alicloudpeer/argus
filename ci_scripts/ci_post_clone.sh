#!/bin/sh
# ci_scripts/ci_post_clone.sh
# Xcode Cloud: clone sonrası çalışır, Secrets.xcconfig'i env var'lardan üretir.
# App Store Connect → Xcode Cloud → Workflow → Environment → bu isimlerdeki
# değişkenleri ayarla. Boş bırakılanlar graceful degrade eder.
set -e

SECRETS="$CI_WORKSPACE/Secrets.xcconfig"

cat > "$SECRETS" <<EOF
// Otomatik oluşturuldu — ci_post_clone.sh
// Xcode Cloud build sırasında App Store Connect env var'larından üretilir.

// === Market Data Providers ================================================
TWELVE_DATA_KEY = ${TWELVE_DATA_KEY:-}
FMP_KEY = ${FMP_KEY:-}
FINNHUB_KEY = ${FINNHUB_KEY:-}
TIINGO_KEY = ${TIINGO_KEY:-}
MARKETSTACK_KEY = ${MARKETSTACK_KEY:-}
ALPHA_VANTAGE_KEY = ${ALPHA_VANTAGE_KEY:-}
EODHD_KEY = ${EODHD_KEY:-}
FRED_KEY = ${FRED_KEY:-}

// === LLM / AI Providers ===================================================
CEREBRAS_KEY = ${CEREBRAS_KEY:-}
GROQ_KEY = ${GROQ_KEY:-}
GEMINI_KEY = ${GEMINI_KEY:-}
GEMINI_KEY_BACKUP = ${GEMINI_KEY_BACKUP:-}
DEEPSEEK_KEY = ${DEEPSEEK_KEY:-}
GLM_KEY = ${GLM_KEY:-}

// === RAG / Pinecone =======================================================
PINECONE_KEY = ${PINECONE_KEY:-}
PINECONE_BASE_URL = ${PINECONE_BASE_URL:-}

// === Turkish Market (BIST) ================================================
BORSAPY_KEY = ${BORSAPY_KEY:-}
BORSAPY_URL = ${BORSAPY_URL:-}

// === Turkish FX ===========================================================
DOVIZCOM_KEY = ${DOVIZCOM_KEY:-}
EOF

echo "[ci_post_clone] Secrets.xcconfig oluşturuldu: $SECRETS"
