#!/usr/bin/env bash
# Scripts/personalize.sh
# -----------------------------------------------------------------------------
# Argus'u kendi Apple Developer hesabına bağlar.
#
# Her abonenin kendi Team ID'si ve Bundle Identifier'ı olduğu için
# project.pbxproj'da geliştiricinin şahsi değerleri hardcoded durur. Bu script
# onları aboneninkilerle değiştirir; yanlış kişinin Team ID'si ile derleme
# yaparsan Xcode "No provisioning profile" hatası verir.
#
# Kullanım (iki mod):
#
#   1) İnteraktif (insan kullanımı için):
#        ./Scripts/personalize.sh
#      Script sana sırasıyla Team ID ve Bundle ID sorar.
#
#   2) Argüman-tabanlı (AI agent / CI kullanımı için):
#        ./Scripts/personalize.sh \
#          --team-id ABCD123456 \
#          --bundle-id com.yourname.argus \
#          [--apple-id you@example.com]   # opsiyonel, sadece yazdırılır
#
#   --dry-run ile hangi değişikliklerin yapılacağını görebilirsin:
#        ./Scripts/personalize.sh --team-id ABCD123456 --bundle-id com.x.y --dry-run
#
# Güvenlik: script project.pbxproj'u yerinde düzenler, önce
# `.xcodeproj/project.pbxproj.bak` dosyasına yedek alır. Yanlış değer
# girdiysen `.bak` dosyasını geri kopyala veya `git checkout --` ile geri al.
# -----------------------------------------------------------------------------

set -euo pipefail

# --- Renkler (TTY varsa) ---
if [[ -t 1 ]]; then
    RED=$'\033[0;31m'
    GREEN=$'\033[0;32m'
    YELLOW=$'\033[0;33m'
    BLUE=$'\033[0;34m'
    BOLD=$'\033[1m'
    RESET=$'\033[0m'
else
    RED=""; GREEN=""; YELLOW=""; BLUE=""; BOLD=""; RESET=""
fi

err()   { printf "%s[hata]%s %s\n" "$RED" "$RESET" "$1" >&2; }
warn()  { printf "%s[uyarı]%s %s\n" "$YELLOW" "$RESET" "$1"; }
info()  { printf "%s[bilgi]%s %s\n" "$BLUE" "$RESET" "$1"; }
ok()    { printf "%s[tamam]%s %s\n" "$GREEN" "$RESET" "$1"; }

usage() {
    cat <<'EOF'
Kullanım:
  Scripts/personalize.sh [--team-id TEAM_ID] [--bundle-id BUNDLE_ID] [--apple-id EMAIL] [--dry-run] [-h|--help]

Argümanlar:
  --team-id TEAM_ID      Apple Developer Team ID (10 karakter, A-Z0-9).
                         Bulma: developer.apple.com → Account → Membership → Team ID.
  --bundle-id BUNDLE_ID  Reverse-DNS form (ör: com.yourname.argus).
                         Benzersiz olmalı; Apple'da aynı bundle ID iki kere register edilemez.
  --apple-id EMAIL       (Opsiyonel) Apple Developer hesabının email'i. project.pbxproj'a
                         yazılmaz — sadece doğrulama çıktısında gösterilir. Apple ID
                         aslında Xcode Preferences → Accounts'tan yönetilir.
  --dry-run              Hiçbir şey yazma, sadece değişecekleri göster.
  -h, --help             Bu yardımı göster.

Argüman verilmezse script interaktif modda çalışır ve sorar.
EOF
}

# --- Parametre parse ---
TEAM_ID=""
BUNDLE_ID=""
APPLE_ID=""
DRY_RUN=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --team-id)   TEAM_ID="${2:-}"; shift 2 ;;
        --bundle-id) BUNDLE_ID="${2:-}"; shift 2 ;;
        --apple-id)  APPLE_ID="${2:-}"; shift 2 ;;
        --dry-run)   DRY_RUN=1; shift ;;
        -h|--help)   usage; exit 0 ;;
        *)           err "Bilinmeyen argüman: $1"; usage; exit 2 ;;
    esac
done

# --- Proje kökü tespiti ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PBXPROJ="$PROJECT_ROOT/argus.xcodeproj/project.pbxproj"

if [[ ! -f "$PBXPROJ" ]]; then
    err "argus.xcodeproj/project.pbxproj bulunamadı."
    err "Bu script'i repo kökünden çalıştırdığından emin ol: $PROJECT_ROOT"
    exit 1
fi

# --- Mevcut değerleri oku ---
# project.pbxproj'da `DEVELOPMENT_TEAM = XXXXXXXXXX;` ve
# `PRODUCT_BUNDLE_IDENTIFIER = xxx.yyy.zzz;` satırları bulunur. Test target
# kendi buildSettings bloğunda (içinde TEST_HOST = ... satırı geçer) ayrı bir
# bundle ID kullanır; ikisini aynıya çekersek App Store Connect / Xcode
# "duplicate bundle identifier" hatası verip IPA export kırılır. Bu yüzden
# block-aware okuyup ana ve test bundle ID'leri ayrı tutuyoruz.
current_team=$(grep -m1 -E '^[[:space:]]*DEVELOPMENT_TEAM = ' "$PBXPROJ" \
                 | sed -E 's/^[[:space:]]*DEVELOPMENT_TEAM = ([^;]+);.*$/\1/' \
                 | tr -d '"' | tr -d '[:space:]' || true)

# awk: her `buildSettings = { ... };` bloğunu izle. Blok kapanırken,
# TEST_HOST görüldüyse blokta yakalanan bundle ID test target'a, yoksa
# ana app'e ait sayılır. Birden çok config (Debug/Release) için ilk
# karşılaşılan değer kullanılır — Debug ve Release'in aynı değer taşıması
# beklenir (Apple kuralı).
read_bundles=$(awk '
    /buildSettings = \{/ {
        in_block = 1; has_test_host = 0; cur = ""
        next
    }
    in_block && /^[[:space:]]*\};[[:space:]]*$/ {
        if (cur != "") {
            if (has_test_host) {
                if (test_bundle == "") test_bundle = cur
            } else {
                if (main_bundle == "") main_bundle = cur
            }
        }
        in_block = 0
        next
    }
    in_block && /TEST_HOST[[:space:]]*=/ { has_test_host = 1 }
    in_block && /^[[:space:]]*PRODUCT_BUNDLE_IDENTIFIER[[:space:]]*=/ {
        v = $0
        sub(/^[[:space:]]*PRODUCT_BUNDLE_IDENTIFIER[[:space:]]*=[[:space:]]*/, "", v)
        sub(/;.*$/, "", v)
        gsub(/"/, "", v)
        gsub(/[[:space:]]/, "", v)
        cur = v
    }
    END { printf "%s\t%s\n", main_bundle, test_bundle }
' "$PBXPROJ")

current_main_bundle="${read_bundles%%	*}"
current_test_bundle="${read_bundles##*	}"

if ! grep -qE '^[[:space:]]*DEVELOPMENT_TEAM = ' "$PBXPROJ"; then
    err "project.pbxproj içinde DEVELOPMENT_TEAM satırı bulunamadı."
    err "Repo bozulmuş olabilir. 'git status' kontrol et."
    exit 1
fi
if [[ -z "$current_main_bundle" ]]; then
    err "project.pbxproj içinde ana app target'ı için PRODUCT_BUNDLE_IDENTIFIER bulunamadı."
    err "(TEST_HOST içermeyen buildSettings bloğunda arandı.)"
    err "Repo bozulmuş olabilir. 'git status' kontrol et."
    exit 1
fi

info "Şu anki değerler:"
info "  DEVELOPMENT_TEAM            = $current_team"
info "  PRODUCT_BUNDLE_IDENTIFIER   = $current_main_bundle  (ana app)"
if [[ -n "$current_test_bundle" ]]; then
    info "  PRODUCT_BUNDLE_IDENTIFIER   = $current_test_bundle  (test target)"
fi

# --- İnteraktif mod (argüman yoksa sor) ---
is_interactive() {
    [[ -t 0 && -t 1 ]]
}

prompt_if_empty() {
    local var_name="$1"
    local label="$2"
    local hint="$3"
    if [[ -z "${!var_name}" ]]; then
        if ! is_interactive; then
            err "$label verilmedi ve script TTY'siz (non-interactive) çalışıyor."
            err "Agent/CI ortamında --team-id ve --bundle-id argümanlarını açıkça ver."
            exit 2
        fi
        printf "\n%s%s%s\n" "$BOLD" "$label" "$RESET"
        printf "  %s\n" "$hint"
        printf "  Değer: "
        IFS= read -r value || true
        value="${value//[[:space:]]/}"
        printf -v "$var_name" '%s' "$value"
    fi
}

prompt_if_empty TEAM_ID \
    "Apple Developer Team ID" \
    "10 karakter büyük harf + rakam. developer.apple.com → Account → Membership → Team ID"

prompt_if_empty BUNDLE_ID \
    "Bundle Identifier" \
    "Reverse-DNS. Örn: com.senin-adın.argus (benzersiz olmalı)"

# Apple ID opsiyonel — sadece interaktif'te sor, boş geçilebilir
if [[ -z "$APPLE_ID" ]] && is_interactive; then
    printf "\n%sApple ID (opsiyonel)%s\n" "$BOLD" "$RESET"
    printf "  Enter'a basarak atlayabilirsin. Sadece doğrulama çıktısında gösterilir.\n"
    printf "  Email: "
    IFS= read -r APPLE_ID || true
fi

# --- Validasyon ---
validate_team_id() {
    if [[ ! "$TEAM_ID" =~ ^[A-Z0-9]{10}$ ]]; then
        err "Team ID geçersiz: '$TEAM_ID'"
        err "Beklenen: 10 karakter, yalnızca A-Z ve 0-9 (büyük harf)."
        err "Örnek: ABCD123456"
        return 1
    fi
}

validate_bundle_id() {
    # Reverse-DNS: en az iki parça nokta ile ayrılmış, her parça harf/rakam/tire
    # Apple kuralı: ASCII, nokta ile ayrılmış, her segment [a-zA-Z0-9-]
    if [[ ! "$BUNDLE_ID" =~ ^[a-zA-Z][a-zA-Z0-9-]*(\.[a-zA-Z][a-zA-Z0-9-]*)+$ ]]; then
        err "Bundle ID geçersiz: '$BUNDLE_ID'"
        err "Beklenen reverse-DNS: en az iki bileşen, her biri harfle başlar."
        err "Örnek: com.yourname.argus"
        return 1
    fi
}

validate_apple_id() {
    # Boşsa OK (opsiyonel). Doluysa çok temel email kontrolü.
    if [[ -z "$APPLE_ID" ]]; then
        return 0
    fi
    if [[ ! "$APPLE_ID" =~ ^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$ ]]; then
        err "Apple ID email formatı geçersiz: '$APPLE_ID'"
        return 1
    fi
}

validate_team_id
validate_bundle_id
validate_apple_id

# --- Yeni bundle ID'leri hesapla ---
# Test target'a, ana app bundle ID'sinin altında ayrı bir bundle ID veriyoruz.
# Orijinal suffix'i (örn: "argusTests") koruruz; tespit edemezsek "Tests"
# default'una düşeriz. İki target'a aynı ID atamak Xcode/App Store Connect'te
# "duplicate bundle identifier" hatası verir — bu script'in eski hâli tam da
# bunu yapıyordu.
new_main_bundle="$BUNDLE_ID"
new_test_bundle=""
if [[ -n "$current_test_bundle" ]]; then
    if [[ "$current_test_bundle" == "$current_main_bundle".* ]]; then
        test_suffix="${current_test_bundle#"$current_main_bundle".}"
    else
        warn "Test bundle ID ($current_test_bundle) ana app'in ($current_main_bundle) child'ı görünmüyor."
        warn "Suffix tespit edilemedi; 'Tests' default'u kullanılacak."
        test_suffix="Tests"
    fi
    new_test_bundle="$BUNDLE_ID.$test_suffix"
fi

# --- Değişiklik özeti ---
printf "\n%sUygulanacak değişiklikler:%s\n" "$BOLD" "$RESET"
printf "  DEVELOPMENT_TEAM             %s  →  %s\n" "$current_team"        "$TEAM_ID"
printf "  PRODUCT_BUNDLE_IDENTIFIER    %s  →  %s   (ana app)\n" "$current_main_bundle" "$new_main_bundle"
if [[ -n "$current_test_bundle" ]]; then
    printf "  PRODUCT_BUNDLE_IDENTIFIER    %s  →  %s   (test target)\n" "$current_test_bundle" "$new_test_bundle"
fi
if [[ -n "$APPLE_ID" ]]; then
    printf "  Apple ID (info only)         %s\n" "$APPLE_ID"
fi

if [[ "$DRY_RUN" -eq 1 ]]; then
    warn "--dry-run: hiçbir dosya değiştirilmedi."
    exit 0
fi

# Aynı değerler → değişikliğe gerek yok
if [[ "$current_team" == "$TEAM_ID" \
   && "$current_main_bundle" == "$new_main_bundle" \
   && "$current_test_bundle" == "$new_test_bundle" ]]; then
    ok "Değerler zaten güncel, değişiklik yapılmadı."
    exit 0
fi

# İnteraktif modda onay al
if is_interactive; then
    printf "\nOnaylıyor musun? [e/H] "
    IFS= read -r confirm || true
    case "$confirm" in
        e|E|y|Y|yes|YES|evet|EVET) ;;
        *) warn "İptal edildi."; exit 0 ;;
    esac
fi

# --- Yedek al ---
BACKUP="$PBXPROJ.bak"
cp "$PBXPROJ" "$BACKUP"
info "Yedek: $BACKUP"

# --- sed ile değiştir ---
# BSD sed (macOS) ve GNU sed (Linux) arasında `-i` davranışı farklı: macOS -i ''
# gerektirir, GNU gerektirmez. Portable yol: -i.tmp kullan, sonra .tmp'yi sil.
#
# Bundle ID'leri tam-eşleşme ile değiştiriyoruz (eski `[^;]+;` wildcard'ı
# yerine), çünkü ana ve test target'ı tek wildcard tek değere düşürüyordu —
# duplicate bundle identifier hatasının kök sebebi buydu. Bundle ID
# format'ında regex meta char olarak yalnız `.` var, onu da literal'a
# escape ediyoruz.
escape_dots() { printf '%s' "$1" | sed -e 's/\./\\./g'; }
main_pat=$(escape_dots "$current_main_bundle")

sed_args=(-E -e "s|^([[:space:]]*DEVELOPMENT_TEAM = )[^;]+;|\1$TEAM_ID;|g")
# Test substitution'ı ana'dan ÖNCE koyuyoruz: test bundle ID, ana bundle
# ID'nin prefix'iyle başlıyor (com.x.argus.argusTests / com.x.argus). Her
# satırın `;` ile kapanması sayesinde pattern'lar zaten birbirine sızmaz,
# ama uzun olanı önce yazmak ekstra güvence.
if [[ -n "$current_test_bundle" ]]; then
    test_pat=$(escape_dots "$current_test_bundle")
    sed_args+=(-e "s|^([[:space:]]*PRODUCT_BUNDLE_IDENTIFIER = )$test_pat;|\1$new_test_bundle;|g")
fi
sed_args+=(-e "s|^([[:space:]]*PRODUCT_BUNDLE_IDENTIFIER = )$main_pat;|\1$new_main_bundle;|g")

sed "${sed_args[@]}" -i.tmp "$PBXPROJ"
rm -f "$PBXPROJ.tmp"

# --- Doğrula ---
# Hem ana hem test bundle ID için yeni değerin occurrence sayısını sayıyoruz;
# sıfır olursa replace çalışmamış demektir → yedekten geri yükle.
team_count=$(grep -cE "^[[:space:]]*DEVELOPMENT_TEAM = $TEAM_ID;" "$PBXPROJ" || true)
main_new_pat=$(escape_dots "$new_main_bundle")
main_count=$(grep -cE "^[[:space:]]*PRODUCT_BUNDLE_IDENTIFIER = $main_new_pat;" "$PBXPROJ" || true)
test_count=0
if [[ -n "$current_test_bundle" ]]; then
    test_new_pat=$(escape_dots "$new_test_bundle")
    test_count=$(grep -cE "^[[:space:]]*PRODUCT_BUNDLE_IDENTIFIER = $test_new_pat;" "$PBXPROJ" || true)
fi

rollback=0
if [[ "$team_count" -eq 0 || "$main_count" -eq 0 ]]; then rollback=1; fi
if [[ -n "$current_test_bundle" && "$test_count" -eq 0 ]]; then rollback=1; fi
# Ek güvence: ana ve test bundle ID gerçekten farklı kaldı mı? Bu invariant
# kırılırsa Xcode/App Store Connect "duplicate bundle identifier" hatası
# verir; eski script'in tek hatası tam buydu.
if [[ -n "$current_test_bundle" && "$new_main_bundle" == "$new_test_bundle" ]]; then
    err "Ana app ve test target için aynı bundle ID üretildi: $new_main_bundle"
    rollback=1
fi

if [[ "$rollback" -eq 1 ]]; then
    err "sed değişikliği beklendiği gibi uygulanmadı (team=$team_count, main=$main_count, test=$test_count)."
    err "Yedekten geri yükleniyor..."
    mv "$BACKUP" "$PBXPROJ"
    exit 1
fi

ok "DEVELOPMENT_TEAM değiştirildi ($team_count occurrence)"
ok "PRODUCT_BUNDLE_IDENTIFIER (ana app) değiştirildi ($main_count occurrence)"
if [[ -n "$current_test_bundle" ]]; then
    ok "PRODUCT_BUNDLE_IDENTIFIER (test target) değiştirildi ($test_count occurrence) → $new_test_bundle"
fi

printf "\n%sSonraki adımlar:%s\n" "$BOLD" "$RESET"
cat <<EOF
  1) Xcode → Preferences (⌘,) → Accounts → Apple ID'ni ekle${APPLE_ID:+ ($APPLE_ID)}
  2) Proje navigator → argus target → Signing & Capabilities sekmesi
     • Team: listeden senin Team ID'n ($TEAM_ID) seçili olmalı
     • "Automatically manage signing" işaretli kalsın
  3) Xcode provisioning profile'ı otomatik oluşturacak. Bunun için:
     • Cihazı Mac'e bağla (ilk sefer USB gerekli, sonra Wi-Fi yeter)
     • Cihaz Apple ID'ne kayıtlı olmalı (ücretsiz account'ta 3 cihaz limiti)
  4) Secrets.xcconfig'i düzenle (kopyala: Secrets.xcconfig.example)
  5) Xcode'da Product → Build (⌘B) — derleme başarılı olmalıysa
     Product → Run (⌘R) — cihazda başlatır

Yanlış değer girdiysen geri almak için:
  cp $BACKUP $PBXPROJ

Veya git ile:
  git checkout -- argus.xcodeproj/project.pbxproj
EOF

ok "Argus, $BUNDLE_ID bundle kimliği ile Team $TEAM_ID'ye bağlandı."
