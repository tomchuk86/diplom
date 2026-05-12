#!/usr/bin/env bash
set -euo pipefail

# QEMU с UART16550_COSIM → TCP :1234 → bridge_dpi (запускается из ModelSim run_cosim.do).
# Сначала дождитесь в симуляторе строки [BRIDGE] waiting for QEMU on 127.0.0.1:1234...
#
#   cd /path/to/diplom && bash qemu2/scripts/run_uart16550_cosim_full.sh

DIPLOM_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

export UART16550_COSIM="${UART16550_COSIM:-1}"
export UART_COSIM_LOG="${UART_COSIM_LOG:-1}"

if command -v ss >/dev/null 2>&1; then
  if ss -ltn 2>/dev/null | grep -q ':1234'; then
    echo "INFO: порт 1234 уже слушается (вероятно bridge готов)." >&2
  else
    echo "WARNING: на :1234 никто не слушает. Запустите в другом терминале: cd $DIPLOM_ROOT/qemu2/tests/rtl/uart_16550 && vsim -c -do run_cosim.do" >&2
    echo "         QEMU при старте cosim будет пытаться подключиться к bridge." >&2
  fi
fi

exec bash "$DIPLOM_ROOT/qemu2/scripts/run_uart16550_qemu_telnet.sh"
