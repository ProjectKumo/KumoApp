#!/usr/bin/env python3
"""
KumoApp i18n Scanner
Scans Swift source files for hardcoded strings that should be localized.
Outputs structured JSON for CI integration.

Usage:
    python3 i18n_scanner.py [--fix] [--output report.json]
"""
import os
import sys
import json
import re
import argparse
from pathlib import Path

# SwiftUI view components that typically contain user-facing text
UI_PATTERNS = [
    (r'Text\s*\(\s*"([^"]+)"', "Text"),
    (r'Button\s*\(\s*"([^"]+)"', "Button"),
    (r'Label\s*\(\s*"([^"]+)"', "Label"),
    (r'Section\s*\(\s*"([^"]+)"', "Section"),
    (r'Picker\s*\(\s*"([^"]+)"', "Picker"),
    (r'Toggle\s*\(\s*"([^"]+)"', "Toggle"),
    (r'navigationTitle\s*\(\s*"([^"]+)"', "navigationTitle"),
    (r'\.badge\s*\(\s*"([^"]+)"', "badge"),
    (r'Placeholder\s*\(\s*"([^"]+)"', "Placeholder"),
    (r'ContentUnavailableView\s*\(\s*"([^"]+)"', "ContentUnavailableView"),
    (r'Alert\s*\(\s*"([^"]+)"', "Alert"),
    (r'\.alert\s*\(\s*"([^"]+)"', "alert"),
    (r'ConfirmationDialog\s*\(\s*"([^"]+)"', "ConfirmationDialog"),
    (r'\.confirmationDialog\s*\(\s*"([^"]+)"', "confirmationDialog"),
    (r'NavigationLink\s*\(\s*"([^"]+)"', "NavigationLink"),
    (r'Link\s*\(\s*"([^"]+)"', "Link"),
]

# Notification / programmatic text
NOTIFICATION_PATTERNS = [
    (r'\.title\s*=\s*"([^"]+)"', "notificationTitle"),
    (r'\.subtitle\s*=\s*"([^"]+)"', "notificationSubtitle"),
    (r'\.body\s*=\s*"([^"]+)"', "notificationBody"),
]

# Patterns that indicate already-localized usage
LOCALIZED_INDICATORS = [
    "String(localized:",
    "LocalizedStringResource(",
    "NSLocalizedString(",
]

# Strings to skip (debug logs, identifiers, URLs, etc.)
SKIP_PREFIXES = ["http", "https", "/", "./", "com.", "io.", "org."]
SKIP_SUFFIXES = [".swift", ".json", ".yaml", ".yml", ".md", ".txt", ".log", ".png", ".jpg", ".pdf"]
SKIP_SUBSTRINGS = ["#Preview", "PreviewProvider", "@main", "fatalError(", "assertionFailure("]

def load_xcstrings_keys(path: str) -> set:
    """Load existing localization keys from .xcstrings file."""
    try:
        with open(path, 'r') as f:
            data = json.load(f)
        return set(data.get("strings", {}).keys())
    except (FileNotFoundError, json.JSONDecodeError):
        return set()

def find_swift_files(directory: str) -> list:
    """Recursively find all .swift files."""
    files = []
    for root, _, filenames in os.walk(directory):
        for name in filenames:
            if name.endswith('.swift'):
                files.append(os.path.join(root, name))
    return sorted(files)

def is_user_facing(text: str) -> bool:
    """Heuristic to determine if a string is user-facing UI text."""
    if len(text) < 2:
        return False
    if text.isdigit() or all(c in '0123456789.' for c in text):
        return False
    for prefix in SKIP_PREFIXES:
        if text.startswith(prefix):
            return False
    for suffix in SKIP_SUFFIXES:
        if text.endswith(suffix):
            return False
    # Single words that are likely code identifiers
    words = text.split()
    if len(words) == 1 and not text[0].isupper() and text.isalpha():
        # Exception: common UI labels
        common_ui = {"OK", "Cancel", "Refresh", "Start", "Stop", "Settings", "About", 
                     "General", "Help", "Error", "Warning", "Success", "Delete", "Apply",
                     "Install", "Remove", "Back", "Next", "Done", "Save", "Edit"}
        if text not in common_ui:
            return False
    return True

def scan_file(filepath: str, existing_keys: set) -> list:
    """Scan a single Swift file for hardcoded strings."""
    issues = []
    try:
        with open(filepath, 'r') as f:
            lines = f.readlines()
    except UnicodeDecodeError:
        return issues
    
    for idx, line in enumerate(lines):
        line_num = idx + 1
        stripped = line.strip()
        
        # Skip comments and imports
        if stripped.startswith('//') or stripped.startswith('import ') or stripped.startswith('/*'):
            continue
        
        # Skip if already localized
        if any(indicator in line for indicator in LOCALIZED_INDICATORS):
            continue

        # Skip lines with string interpolation (\(…)) — these are dynamic and
        # should use String(format: String(localized: "key"), …) instead of
        # a plain literal.  The scanner only flags *simple* literal strings.
        if r'\(' in line:
            continue

        for pattern, context in UI_PATTERNS + NOTIFICATION_PATTERNS:
            matches = re.findall(pattern, line)
            for text in matches:
                if is_user_facing(text) and text not in existing_keys:
                    issues.append({
                        "file": filepath,
                        "line": line_num,
                        "context": context,
                        "text": text,
                        "suggestion": f'Text(String(localized: "{text}"))'
                    })
    
    return issues

def main():
    parser = argparse.ArgumentParser(description="Scan Swift files for unlocalized strings")
    parser.add_argument("--sources", default="./Sources", help="Source directory to scan")
    parser.add_argument("--xcstrings", default="./Sources/KumoCoreKit/Resources/Localizable.xcstrings",
                        help="Path to .xcstrings file")
    parser.add_argument("--output", help="Output JSON report path")
    parser.add_argument("--summary", action="store_true", help="Print summary only")
    args = parser.parse_args()
    
    existing_keys = load_xcstrings_keys(args.xcstrings)
    swift_files = find_swift_files(args.sources)
    
    all_issues = []
    for filepath in swift_files:
        issues = scan_file(filepath, existing_keys)
        all_issues.extend(issues)
    
    # Group by file
    by_file = {}
    for issue in all_issues:
        by_file.setdefault(issue["file"], []).append(issue)
    
    # Group by unique string
    unique_strings = set(issue["text"] for issue in all_issues)
    
    report = {
        "summary": {
            "existing_keys": len(existing_keys),
            "swift_files_scanned": len(swift_files),
            "total_occurrences": len(all_issues),
            "unique_strings": len(unique_strings),
        },
        "files": {
            path.replace(args.sources + "/", ""): issues
            for path, issues in sorted(by_file.items(), key=lambda x: -len(x[1]))
        },
        "unique_strings": sorted(unique_strings),
    }
    
    if args.output:
        with open(args.output, 'w') as f:
            json.dump(report, f, indent=2)
        print(f"Report saved to {args.output}")
    
    if not args.summary and not args.output:
        print(json.dumps(report, indent=2))
    else:
        print(f"i18n Scan Summary")
        print(f"=================")
        print(f"Existing keys in catalog: {len(existing_keys)}")
        print(f"Swift files scanned:      {len(swift_files)}")
        print(f"Unlocalized occurrences:  {len(all_issues)}")
        print(f"Unique strings missing:   {len(unique_strings)}")
        print(f"")
        print("Top 10 files:")
        for path, issues in sorted(by_file.items(), key=lambda x: -len(x[1]))[:10]:
            short = path.replace(args.sources + "/", "")
            print(f"  {short}: {len(issues)}")

if __name__ == "__main__":
    main()
