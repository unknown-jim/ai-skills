---
name: send-email
description: Sends the user a plain-text email via Resend HTTPS API (preferred) or SMTP fallback. Use only when the user explicitly asks to email them, including 发邮件, 发到邮箱, email me, or send email. Do not send unsolicited mail, do not wire this into timers or project automation.
---

# Send Email

One plain-text email, sent on explicit request only. This is a user-level
capability, not project automation: never attach it to a timer, cron entry,
launchd job, git hook, or CI step, and never copy it into a repository.

## 1. Confirm the request

Send only if the user asked in this turn. Explicit triggers:
发邮件 / 发到邮箱 / 发一封邮件 / email me / send email. "做完发我邮箱" also
counts — send once the work is done.

Not a trigger: finishing a task, a milestone, a long-running job completing, a
build going green. If there is no explicit request, do not send, and say plainly
that no email was sent.

Never put an API key, password, or token into the mail body or into chat.
Never `pip install` anything for this — the script is stdlib-only.

## 2. Draft the message

State the subject and the gist of the body in chat first, then send. If the user
already supplied the full text, use it verbatim — do not expand it.

Plain text only. No HTML, no attachments, no CC unless the user asks.

## 3. Send

Body goes over stdin, so it never appears in argv. Use the absolute path — the
working directory is the project root, not this skill directory:

```bash
python3 "$HOME/.agents/skills/send-email/scripts/send.py" --subject "主题" <<'EOF'
正文第一行
正文第二行
EOF
```

(`python3` is what exists on this machine; there is no `python` on PATH.)

Optional: `--env-file /path/to/file` overrides the credential search order.

## 4. Report the result

The script prints exactly one line of JSON. Read `sent` and tell the user
success or failure, quoting the `error` field on failure. Do not echo the
`Authorization` header, the password, or the API key into chat.

```json
{"sent": true, "transport": "api", "id": "…", "subject": "…"}
{"sent": true, "transport": "smtp", "subject": "…"}
{"sent": false, "transport": "api", "error": "…", "subject": "…"}
```

Exit codes: `0` sent, `1` transport failure, `2` configuration missing.

## 5. Missing configuration

Never guess a password, host, or recipient. On exit code 2, tell the user which
variable is missing and which file to put it in — then stop.

Credentials are read from the first readable file of:

1. `$MAIL_ENV_FILE`
2. `~/.config/agent-mail.env`
3. `/etc/portfolio-review/smtp.env`

Variables:

| Variable | Meaning |
| --- | --- |
| `MAIL_TO` | recipient; falls back to `INVESTMENT_ALERT_RECIPIENT` |
| `RESEND_API_KEY` | if present, the Resend API is the only transport used |
| `RESEND_SENDER` | optional, defaults to `onboarding@resend.dev` |
| `SMTP_HOST` `SMTP_PORT` `SMTP_USERNAME` `SMTP_PASSWORD` `SMTP_SENDER` | required only when there is no `RESEND_API_KEY` |

If none of the three files is readable, write
`~/.config/agent-mail.env.example` listing the variables with empty values (no
secrets), tell the user to fill in a real `~/.config/agent-mail.env`, and stop.
Do not claim the mail was sent.

## Transport rules

- `RESEND_API_KEY` present → `POST https://api.resend.com/emails` only. Do not
  fall back to SMTP when the API call fails; report the failure.
- No key → SMTP. Port 465 uses implicit TLS, any other port uses STARTTLS.
- 30s timeout, single attempt. No queue, no outbox, no retry loop.
