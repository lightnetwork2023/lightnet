#!/usr/bin/env python3
"""Ping MikroTik devices and update app_docs without occupying gunicorn login workers."""
from __future__ import annotations

import json
import sys

sys.path.insert(0, '/opt')

from app import run_check_mikrotik_devices  # noqa: E402


def main():
    result = run_check_mikrotik_devices()
    summary = {
        key: result[key]
        for key in ('success', 'checked', 'online', 'offline', 'message')
        if key in result
    }
    print(json.dumps(summary))


if __name__ == '__main__':
    main()
