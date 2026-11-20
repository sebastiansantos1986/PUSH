#!/bin/bash
# Developer: Sebastian Santos — PUSH-DEV-SEBASTIAN-SANTOS
# Jamf Extension Attribute, String. Read-only; never runs PUSH or an updater.
reporter=/Library/Management/PUSH/Tahoe-Campaign/push-tahoe-readiness
if [[ -x "$reporter" ]]; then
  result="$("$reporter" --ea 2>/dev/null)" || result=''
  case "$result" in
    '<result>Tahoe supported</result>'|'<result>Tahoe supported - OS below PUSH minimum</result>'|'<result>Tahoe unsupported - replacement review</result>'|'<result>Above Tahoe - do not downgrade</result>'|'<result>Unverified - IT review</result>') printf '%s\n' "$result";exit 0;;
  esac
fi
printf '<result>Unverified - IT review</result>\n'
