#!/usr/bin/env python3
"""Post GitHub release notes and DMG assets to a Telegram channel."""

from __future__ import annotations

import html as html_module
import json
import os
import re
import sys
import urllib.error
import urllib.request

# Telegram HTML parse_mode tags (https://core.telegram.org/bots/api#html-style).
# Line breaks use literal newlines, not <br>.
ALLOWED_TAGS = {"b", "i", "u", "s", "code", "pre", "a", "tg-spoiler"}


def escape_html_except_allowed(text: str) -> str:
    """Escape text while preserving Telegram-supported HTML tags."""
    result: list[str] = []
    i = 0
    while i < len(text):
        if text[i] == "<":
            match = re.match(r"</?([a-zA-Z][a-zA-Z0-9]*)(?:\s+[^>]*)?>", text[i:])
            if match and match.group(1).lower() in ALLOWED_TAGS:
                result.append(text[i : i + match.end()])
                i += match.end()
                continue
            result.append("&lt;")
        elif text[i] == ">":
            result.append("&gt;")
        elif text[i] == "&":
            result.append("&amp;")
        else:
            result.append(text[i])
        i += 1
    return "".join(result)


def markdown_to_telegram_html(text: str) -> str:
    """Convert a GitHub release Markdown body to Telegram HTML."""
    if not text:
        return ""

    placeholders: dict[str, str] = {}
    ph_counter = [0]

    def protect(content: str, prefix: str) -> str:
        key = f"\x00{prefix}{ph_counter[0]}\x00"
        ph_counter[0] += 1
        placeholders[key] = content
        return key

    text = re.sub(
        r"```(?:\w+)?\n?(.*?)```",
        lambda m: protect(m.group(1), "CB"),
        text,
        flags=re.DOTALL,
    )
    text = re.sub(r"`([^`]+?)`", lambda m: protect(m.group(1), "IC"), text)

    text = re.sub(r"^#{1,6}\s+(.+)$", r"<b>\1</b>", text, flags=re.MULTILINE)
    text = re.sub(r"\*\*(.+?)\*\*", r"<b>\1</b>", text)
    # Skip __bold__ — tokens like latest-amd64.yml break Telegram HTML parsing.
    text = re.sub(r"(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)", r"<i>\1</i>", text)
    text = re.sub(r"~~(.+?)~~", r"<s>\1</s>", text)
    text = re.sub(
        r"\[([^\]]+?)\]\(([^)]+?)\)",
        lambda m: (
            f'<a href="{html_module.escape(m.group(2), quote=True)}">'
            f"{html_module.escape(m.group(1))}</a>"
        ),
        text,
    )
    text = re.sub(r"^(\s*)[-*]\s+(.+)$", r"\1• \2", text, flags=re.MULTILINE)

    for key, content in placeholders.items():
        escaped = html_module.escape(content)
        if key.startswith("\x00CB"):
            text = text.replace(key, f"<pre>{escaped}</pre>")
        else:
            text = text.replace(key, f"<code>{escaped}</code>")

    return escape_html_except_allowed(text)


def telegram_api(bot_token: str, method: str, payload: dict) -> dict:
    req = urllib.request.Request(
        f"https://api.telegram.org/bot{bot_token}/{method}",
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req) as resp:
            return json.load(resp)
    except urllib.error.HTTPError as e:
        body = e.read().decode(errors="replace")
        raise RuntimeError(f"Telegram {method} HTTP {e.code}: {body}") from e


def send_release_message(
    bot_token: str,
    channel_id: str,
    release: dict,
) -> int:
    release_url = release.get("html_url") or release.get("url", "")
    body_html = markdown_to_telegram_html(release.get("body", "") or "")
    link = (
        f'<a href="{html_module.escape(release_url, quote=True)}">'
        "View on GitHub</a>"
    )
    text = f"<b>{html_module.escape(release['name'])}</b>\n\n{body_html}\n\n{link}"

    if len(text) > 4000:
        truncate_at = text.rfind("\n", 0, 3950)
        if truncate_at == -1:
            truncate_at = 3950
        text = text[:truncate_at] + "\n\n<i>... (truncated)</i>"

    try:
        result = telegram_api(
            bot_token,
            "sendMessage",
            {
                "chat_id": channel_id,
                "text": text,
                "parse_mode": "HTML",
                "disable_web_page_preview": False,
            },
        )
    except RuntimeError as error:
        print(f"HTML send failed, retrying as plain text: {error}", file=sys.stderr)
        plain_body = release.get("body", "") or ""
        plain_text = f"{release['name']}\n\n{plain_body}\n\n{release_url}"
        if len(plain_text) > 4000:
            plain_text = plain_text[:3950] + "\n\n... (truncated)"
        result = telegram_api(
            bot_token,
            "sendMessage",
            {
                "chat_id": channel_id,
                "text": plain_text,
                "disable_web_page_preview": False,
            },
        )

    return result["result"]["message_id"]


def load_release() -> dict:
    release_json = os.environ.get("RELEASE_JSON")
    if release_json:
        with open(release_json, encoding="utf-8") as handle:
            payload = json.load(handle)
        if "release" in payload:
            return payload["release"]
        return payload

    event_path = os.environ["GITHUB_EVENT_PATH"]
    with open(event_path, encoding="utf-8") as handle:
        return json.load(handle)["release"]


def main() -> None:
    bot_token = os.environ["BOT_TOKEN"]
    channel_id = os.environ["CHANNEL_ID"]
    release = load_release()

    msg_id = send_release_message(bot_token, channel_id, release)

    try:
        telegram_api(
            bot_token,
            "pinChatMessage",
            {
                "chat_id": channel_id,
                "message_id": msg_id,
                "disable_notification": True,
            },
        )
    except RuntimeError as error:
        print(f"Failed to pin message: {error}", file=sys.stderr)

    for asset in release.get("assets", []):
        name = asset.get("name", "")
        if not name.endswith(".dmg"):
            continue
        download_url = asset.get("browser_download_url") or asset.get("url")
        if not download_url:
            print(f"Skipping {name}: missing download URL", file=sys.stderr)
            continue
        size_kb = asset.get("size", 0) // 1024
        try:
            telegram_api(
                bot_token,
                "sendDocument",
                {
                    "chat_id": channel_id,
                    "document": download_url,
                    "caption": f"{name} ({size_kb} KB)",
                    "reply_to_message_id": msg_id,
                },
            )
        except RuntimeError as error:
            print(f"Failed to send {name}: {error}", file=sys.stderr)

    print("Done: Telegram notification sent")


if __name__ == "__main__":
    main()
