"""Start Spoolman for the Klipper HAOS app.

Equivalent to ``uvicorn spoolman.main:app`` with one change: Spoolman's
Docker check is told that its data directory is persistent. Spoolman looks
for a mount point named exactly like its data directory; here it is
/data/spoolman, inside the app's persistent /data mount, so the check would
print a false "the database will be lost" warning at every start.

Run from /opt/spoolman with Spoolman's virtual environment.
"""

from __future__ import annotations

import os

import spoolman.env
import uvicorn

spoolman.env.is_data_dir_mounted = lambda: True

if __name__ == "__main__":
    uvicorn.run(
        "spoolman.main:app",
        host=os.environ["SPOOLMAN_HOST"],
        port=int(os.environ["SPOOLMAN_PORT"]),
        server_header=False,
    )
