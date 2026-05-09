#!/usr/bin/env python3
from pathlib import Path

qip = Path("soc_system/synthesis/soc_system.qip")
text = qip.read_text()
text = "\n".join(
    line for line in text.splitlines()
    if "hps_sdram_p0.sdc" not in line
) + "\n"
qip.write_text(text)
