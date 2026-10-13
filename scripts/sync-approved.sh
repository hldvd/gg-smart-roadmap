#!/usr/bin/env bash
#
# sync-approved.sh — همگام‌سازی محدوده‌دار نسخه محلی با GitHub برای محتوای مصوب
#
# کاربرد:
#   scripts/sync-approved.sh "<پیام کامیت>" <فایل۱> [فایل۲ ...]
#
# فقط فایل‌های فهرست‌شده commit و push می‌شوند؛ تغییرات نامرتبطِ working tree
# دست نمی‌خورند و منتشر نمی‌شوند. پیش از اعلام موفقیت، یکسانی دو نسخه با Git
# راستی‌آزمایی می‌شود؛ خروجی غیرصفر یعنی موفقیت اعلام نمی‌شود و مورد باز می‌ماند.
#
# فرایند مرجع: AI-GUIDE.md ← «قواعد مستندسازی پیوسته» ← «همگام‌سازی نسخه محلی و GitHub»

set -euo pipefail

die() { echo "❌ $*" >&2; exit 1; }
info() { echo "→ $*"; }

[ "$#" -ge 2 ] || die "کاربرد: scripts/sync-approved.sh \"<پیام کامیت>\" <فایل۱> [فایل۲ ...]"

MSG="$1"; shift

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "درون یک مخزن Git نیستید"
cd "$(git rev-parse --show-toplevel)"

[ -n "$(git config user.name || true)" ] && [ -n "$(git config user.email || true)" ] \
  || die "هویت Git (user.name / user.email) تنظیم نشده است"

BRANCH="$(git rev-parse --abbrev-ref HEAD)"
[ "$BRANCH" != "HEAD" ] || die "در حالت detached head هستید؛ ادامه ممکن نیست"

# ۰) شاخص (index) باید از قبل تمیز باشد تا چیزی خارج از فهرست مصوب منتشر نشود
[ -z "$(git diff --cached --name-only)" ] || die "شاخص Git تمیز نیست؛ ابتدا فایل‌های staged قبلی را تعیین تکلیف کنید"

# ۱) اعتبارسنجی فایل‌های مصوب
for f in "$@"; do
  [ -e "$f" ] || die "فایل وجود ندارد: $f"
  if git check-ignore -q -- "$f"; then
    die "فایل نادیده‌گرفته‌شده (ignored) است و قابل ثبت نیست: $f"
  fi
done

# ۲) افزودن فقط فایل‌های مصوب (شامل فایل جدید و تغییریافته)
git add -A -- "$@"

[ -n "$(git diff --cached --name-only)" ] || die "تغییری در فایل‌های مصوب یافت نشد؛ چیزی ثبت نمی‌شود"

info "فایل‌های مصوبِ در صفِ ثبت:"
git diff --cached --name-status

# ۳) کامیت (بدون amend، بدون force، با پیام داده‌شده)
git commit -q -m "$MSG"
CHEAD="$(git rev-parse --short HEAD)"
info "کامیت انجام شد: $CHEAD"

# ۴) push به شاخهٔ ردیابی‌شده (بدون force)
info "ارسال به origin ..."
git push origin "HEAD:refs/heads/$BRANCH"

# ۵) راستی‌آزمایی وضعیت واقعی هر دو نسخه
git fetch origin --quiet
read -r AHEAD BEHIND <<< "$(git rev-list --left-right --count "origin/$BRANCH"...HEAD)"
if [ "$AHEAD" = "0" ] && [ "$BEHIND" = "0" ]; then
  info "راستی‌آزمایی: HEAD و origin/$BRANCH هم‌ارزند (0 ↔ 0)"
else
  die "همگام‌سازی ناقص است: HEAD جلوتر=$AHEAD ، عقب‌تر=$BEHIND نسبت به origin/$BRANCH — موفقیت اعلام نمی‌شود"
fi

REMAINING="$(git status --porcelain)"
if [ -n "$REMAINING" ]; then
  info "تغییرات نامرتبطِ باقی‌مانده در working tree (منتشر نشدند):"
  echo "$REMAINING"
else
  info "working tree تمیز است."
fi

echo "✅ همگام‌سازی موفق: کامیت $CHEAD در origin/$BRANCH تأیید شد."
