#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""فحص أسرار المحركات النقية — وصل شات (2.0.0)

الموثق في: docs/SELF_HOSTING.md §5، docs/GRAND_PLAN_2.md (1.9.0)，
RUNBOOK_URGENT.md، وترويسات engines/*/README — «يمسح كل ملف في engines/
بحثاً عن رموز ومفاتيح وعناوين مشاريع، والنتيجة صفر».

ماذا يمسح فعلاً:
  1) أنماط مفاتيح معروفة (Google/GitHub/AWS/OpenAI-style/JWT طويل/Supabase)
  2) عناوين مشاريع: روابط *.supabase.co / *.supabase.in ومراجع المشاريع
  3) تعيينات بأسماء الأسرار (key/secret/token/password) بقيمة طويلة —
     مع استثناء القيم السداسية عشرية النقية وأرقام المتجهات الاختبارية
     (RFC 4231 ونظائرها في محركات التشفير)

الخروج: 0 = صفر أسرار (يطبع عدد الملفات الممسوحة) — 1 = وجود مشتبه (يطبقه)
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent / 'engines'
SKIP_DIRS = {'.dart_tool', '.git', 'build', '.pytest_cache'}
SKIP_SUFFIX = {'.lock', '.tar.xz', '.png', '.jpg', '.zip'}

PATTERNS = [
    ('google_api_key', re.compile(r'AIza[0-9A-Za-z_\-]{35}')),
    ('github_token', re.compile(r'gh[pousr]_[A-Za-z0-9]{30,}')),
    ('aws_access_key', re.compile(r'AKIA[0-9A-Z]{16}')),
    ('openai_style', re.compile(r'sk-[A-Za-z0-9_\-]{20,}')),
    ('slack_token', re.compile(r'xox[baprs]-[A-Za-z0-9\-]{10,}')),
    ('supabase_project_url',
     re.compile(r'https://[a-z0-9]{18,}\.supabase\.(co|in|net)')),
    ('long_jwt', re.compile(r'eyJ[A-Za-z0-9_\-]{40,}\.[A-Za-z0-9_\-]{20,}')),
    ('secret_assignment', re.compile(
        r"(?:api[_-]?key|secret|token|password|service[_-]?role)"
        r"\s*[:=]\s*['\"]([^'\"\s]{12,})['\"]", re.IGNORECASE)),
]

HEX_ONLY = re.compile(r'^[0-9a-fA-F]+$')
NUMERIC = re.compile(r'^[0-9.\-]+$')


def looks_like_test_vector(value: str) -> bool:
    """متجهات الاختبار السداسية عشرية وأرقامها ليست أسراراً — استثناء موثق."""
    return bool(HEX_ONLY.match(value) or NUMERIC.match(value))


def scan_file(path: Path):
    findings = []
    try:
        text = path.read_text(encoding='utf-8', errors='ignore')
    except OSError as e:
        print(f'[تحذير] تعذر قراءة {path}: {e}')
        return findings
    for name, pattern in PATTERNS:
        for m in pattern.finditer(text):
            if name == 'secret_assignment':
                value = m.group(1)
                if looks_like_test_vector(value):
                    continue
            line_no = text.count('\n', 0, m.start()) + 1
            findings.append((name, f'{path.relative_to(ROOT.parent)}:{line_no}'))
    return findings


def main() -> int:
    if not ROOT.is_dir():
        print(f'المجلد {ROOT} غير موجود')
        return 2
    files = [p for p in ROOT.rglob('*')
             if p.is_file()
             and not (SKIP_DIRS & set(p.parts))
             and p.suffix not in SKIP_SUFFIX]
    all_findings = []
    for p in files:
        all_findings.extend(scan_file(p))
    if all_findings:
        print(f'❌ {len(all_findings)} مشتبه في {len(files)} ملفاً:')
        for name, loc in all_findings:
            print(f'  - {name}: {loc}')
        return 1
    print(f'✅ صفر أسرار — فُحص {len(files)} ملفاً في engines/ '
          f'بـ{len(PATTERNS)} أنماط (المتجهات السداسية عشرية مستثناة توثيقاً)')
    return 0


if __name__ == '__main__':
    sys.exit(main())
