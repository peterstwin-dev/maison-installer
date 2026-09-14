#!/bin/bash
# install.sh — archived. The one-command installer moved to bootstrap.sh.
#
# You most likely reached this file from an old link or email. Nothing extra
# to do: this hands off to the new script with the same arguments, so an old
#   curl -fsSL .../install.sh | bash -s -- mb_<token>
# still works exactly as before.
#
# For a fresh copy-paste, use the new command instead:
#   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/peterstwin-dev/maison-installer/main/bootstrap.sh)"

set -eo pipefail
exec /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/peterstwin-dev/maison-installer/main/bootstrap.sh)" bash "$@"
