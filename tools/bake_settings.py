#!/usr/bin/env python3
"""Overwrite setting defaults in a properties.xml.

    bake_settings.py <env-file> <properties.xml>

The env file holds `property_id=value` lines. build.sh runs this on a staged
copy only, so values such as the bearer token never reach the repository.
"""

import re
import sys
from xml.sax.saxutils import escape

env_file, path = sys.argv[1], sys.argv[2]

values = {}
for line in open(env_file, encoding="utf-8"):
    line = line.strip()
    if line and not line.startswith("#"):
        key, _, value = line.partition("=")
        values[key.strip()] = value.strip()

xml = open(path, encoding="utf-8").read()
for key, value in values.items():
    pattern = re.compile(r'(<property id="%s" type="[^"]+">)[^<]*(</property>)' % re.escape(key))
    xml, count = pattern.subn(lambda m: m.group(1) + escape(value) + m.group(2), xml)
    if count != 1:
        sys.exit(f"{env_file}: '{key}' is not a property in {path}")

open(path, "w", encoding="utf-8").write(xml)
