#!/usr/bin/env bash
set -euo pipefail

# Сборка цепочки: QEMU (uart-stub + cosim) → гостевой .ko и тест → проверка протокола C.
# Из корня репозитория: bash qemu2/scripts/build_uart16550_stack.sh
#
# Переменные (как в drivers/uart16550_extended/Makefile):
#   BR_HOST, BR_KDIR, BR_CROSS — если Buildroot не в ~/buildroot/output/...

DIPLOM_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BR_HOST="${BR_HOST:-/home/vboxuser/buildroot/output/host}"
BR_KDIR="${BR_KDIR:-/home/vboxuser/buildroot/output/build/linux-6.18.7}"
BR_CROSS="${BR_CROSS:-${BR_HOST}/bin/arm-none-linux-gnueabihf-}"

echo "== ninja: qemu-system-arm =="
cd "$DIPLOM_ROOT/qemu2/build"
ninja qemu-system-arm

echo "== guest: uart16550_demo.ko + test_uart16550_demo (static) =="
cd "$DIPLOM_ROOT/qemu2/drivers/uart16550_extended"
make guest BR_HOST="$BR_HOST" BR_KDIR="$BR_KDIR" BR_CROSS="$BR_CROSS"

echo "== host: uart_cosim protocol unit test =="
cd "$DIPLOM_ROOT/qemu2/tests/rtl/uart_16550"
make -f Makefile.bridgetest check-protocol

echo
echo "OK: qemu2/build/qemu-system-arm, drivers/uart16550_extended/{uart16550_demo.ko,test_uart16550_demo}"
echo
echo "Дальше (полная cosim с RTL):"
echo "  Терминал A: cd $DIPLOM_ROOT/qemu2/tests/rtl/uart_16550 && vsim -c -do run_cosim.do"
echo "  Терминал B: cd $DIPLOM_ROOT && bash qemu2/scripts/run_uart16550_cosim_full.sh"
echo "Без ModelSim (только QEMU + встроенный stub):"
echo "  cd $DIPLOM_ROOT && bash qemu2/scripts/run_uart16550_qemu_telnet.sh"
