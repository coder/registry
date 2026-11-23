from pathlib import Path
import sys


try:
    print(Path(sys.argv[1]).resolve(strict=True))
except (OSError, RuntimeError) as error:
    print(f"Cannot resolve IDE settings symlink: {error}", file=sys.stderr)
    raise SystemExit(1)
