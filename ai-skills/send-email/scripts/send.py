#!/usr/bin/env python3
"""Send the user one plain-text email. Stdlib only.

Transport is decided once, up front:
  RESEND_API_KEY present -> Resend HTTPS API, and nothing else.
  otherwise              -> SMTP.
There is deliberately no queue, no retry loop, and no API->SMTP fallback:
a failure must surface to the agent, not get silently re-routed.

Body arrives on stdin so it never lands in argv or in a process listing.
Exactly one line of JSON goes to stdout.
"""

import argparse
import json
import os
import smtplib
import ssl
import sys
import urllib.error
import urllib.request
from email.message import EmailMessage

ENV_FILE_CANDIDATES = (
    os.environ.get("MAIL_ENV_FILE"),
    os.path.expanduser("~/.config/agent-mail.env"),
    "/etc/portfolio-review/smtp.env",
)

RESEND_URL = "https://api.resend.com/emails"
DEFAULT_RESEND_SENDER = "onboarding@resend.dev"
USER_AGENT = "cursor-agent-mail/1.0"  # Cloudflare blocks urllib's default UA (1010)
TIMEOUT = 30

SECRET_KEYS = ("RESEND_API_KEY", "SMTP_PASSWORD")

# Keys this script reads. Anything else in the env file is ignored.
CONFIG_KEYS = (
    "MAIL_TO",
    "INVESTMENT_ALERT_RECIPIENT",
    "RESEND_API_KEY",
    "RESEND_SENDER",
    "SMTP_HOST",
    "SMTP_PORT",
    "SMTP_USERNAME",
    "SMTP_PASSWORD",
    "SMTP_SENDER",
)


def out(payload, code=0):
    """Emit one line of JSON and exit. Never raises past this point."""
    sys.stdout.write(json.dumps(payload, ensure_ascii=False) + "\n")
    sys.stdout.flush()
    raise SystemExit(code)


def parse_env_file(path):
    """KEY=VALUE lines. Blank lines and # comments ignored. Quotes stripped."""
    values = {}
    with open(path, "r", encoding="utf-8", errors="replace") as fh:
        for raw in fh:
            line = raw.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, _, value = line.partition("=")
            key = key.strip()
            if key.startswith("export "):
                key = key[len("export "):].strip()
            value = value.strip()
            if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
                value = value[1:-1]
            if key:
                values[key] = value
    return values


def load_config(explicit_path):
    """Process env as the base; the first readable env file wins over it."""
    config = {k: v for k, v in os.environ.items() if k in CONFIG_KEYS and v}
    candidates = (explicit_path,) if explicit_path else ENV_FILE_CANDIDATES
    used = None
    for path in candidates:
        if not path:
            continue
        expanded = os.path.expanduser(path)
        if os.access(expanded, os.R_OK) and os.path.isfile(expanded):
            config.update({k: v for k, v in parse_env_file(expanded).items() if v})
            used = expanded
            break
    return config, used, [os.path.expanduser(p) for p in candidates if p]


def redactor(config):
    """Scrub any secret value out of a string before it reaches stdout."""
    secrets = [config.get(k) for k in SECRET_KEYS]
    secrets = [s for s in secrets if s and len(s) >= 4]

    def scrub(text):
        text = str(text)
        for secret in secrets:
            text = text.replace(secret, "***")
        return text

    return scrub


def send_via_api(config, recipient, subject, body, scrub):
    sender = config.get("RESEND_SENDER") or DEFAULT_RESEND_SENDER
    payload = json.dumps(
        {"from": sender, "to": [recipient], "subject": subject, "text": body}
    ).encode("utf-8")
    request = urllib.request.Request(
        RESEND_URL,
        data=payload,
        method="POST",
        headers={
            "Authorization": "Bearer " + config["RESEND_API_KEY"],
            "Content-Type": "application/json",
            "Accept": "application/json",
            "User-Agent": USER_AGENT,
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=TIMEOUT) as response:
            raw = response.read().decode("utf-8", errors="replace")
    except urllib.error.HTTPError as exc:
        detail = ""
        try:
            detail = exc.read().decode("utf-8", errors="replace")[:300]
        except Exception:
            pass
        out(
            {
                "sent": False,
                "transport": "api",
                "error": scrub("HTTP %s: %s" % (exc.code, detail)),
                "subject": subject,
            },
            1,
        )
    except Exception as exc:  # URLError, timeout, ssl, ...
        out(
            {
                "sent": False,
                "transport": "api",
                "error": scrub("%s: %s" % (type(exc).__name__, exc)),
                "subject": subject,
            },
            1,
        )

    try:
        message_id = json.loads(raw).get("id", "")
    except ValueError:
        message_id = ""
    out({"sent": True, "transport": "api", "id": message_id, "subject": subject})


def send_via_smtp(config, recipient, subject, body, scrub):
    message = EmailMessage()
    message["From"] = config["SMTP_SENDER"]
    message["To"] = recipient
    message["Subject"] = subject
    message.set_content(body)

    try:
        port = int(config["SMTP_PORT"])
    except ValueError:
        out({"sent": False, "error": "missing SMTP_PORT (must be an integer)"}, 2)

    try:
        context = ssl.create_default_context()
        if port == 465:
            server = smtplib.SMTP_SSL(
                config["SMTP_HOST"], port, timeout=TIMEOUT, context=context
            )
        else:
            server = smtplib.SMTP(config["SMTP_HOST"], port, timeout=TIMEOUT)
        with server:
            if port != 465:
                server.starttls(context=context)
            server.login(config["SMTP_USERNAME"], config["SMTP_PASSWORD"])
            server.send_message(message)
    except Exception as exc:
        out(
            {
                "sent": False,
                "transport": "smtp",
                "error": scrub("%s: %s" % (type(exc).__name__, exc)),
                "subject": subject,
            },
            1,
        )

    out({"sent": True, "transport": "smtp", "subject": subject})


def main():
    parser = argparse.ArgumentParser(
        description="Send one plain-text email. Body is read from stdin."
    )
    parser.add_argument("--subject", required=True)
    parser.add_argument(
        "--env-file",
        help="override the credential file search path",
    )
    args = parser.parse_args()

    config, used_file, searched = load_config(args.env_file)
    scrub = redactor(config)

    body = sys.stdin.read()
    if not body.strip():
        out({"sent": False, "error": "missing body (nothing on stdin)"}, 2)

    if used_file is None:
        out(
            {
                "sent": False,
                "error": "missing credential file; none readable: "
                + ", ".join(searched),
            },
            2,
        )

    recipient = config.get("MAIL_TO") or config.get("INVESTMENT_ALERT_RECIPIENT")
    if not recipient:
        out(
            {
                "sent": False,
                "error": "missing MAIL_TO (or INVESTMENT_ALERT_RECIPIENT) in "
                + used_file,
            },
            2,
        )

    if config.get("RESEND_API_KEY"):
        send_via_api(config, recipient, args.subject, body, scrub)

    missing = [
        k
        for k in ("SMTP_HOST", "SMTP_PORT", "SMTP_USERNAME", "SMTP_PASSWORD", "SMTP_SENDER")
        if not config.get(k)
    ]
    if missing:
        out(
            {
                "sent": False,
                "error": "missing %s in %s (no RESEND_API_KEY either)"
                % (", ".join(missing), used_file),
            },
            2,
        )

    send_via_smtp(config, recipient, args.subject, body, scrub)


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except KeyboardInterrupt:
        out({"sent": False, "error": "interrupted"}, 1)
    except Exception as exc:
        # Never let a traceback out: it can carry argv and environment.
        out({"sent": False, "error": "%s: unexpected failure" % type(exc).__name__}, 1)
