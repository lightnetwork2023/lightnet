#!/usr/bin/env python3
"""NetFlow aggregator disabled. Exits without processing."""
import sys
print('netflow disabled', file=sys.stderr)
sys.exit(0)
