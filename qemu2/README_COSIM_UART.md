# UART 16550: QEMU ↔ RTL cosim (TCP bridge + DPI)

Полная цепочка **гость Linux → драйвер → MMIO в QEMU → TCP → `bridge_dpi.so` → DPI → APB RTL** задаётся **`UART16550_COSIM=1`** (или **`socket`**, или любое ненулевое значение **кроме** **`dpi`**).

Режим **`UART16550_COSIM=dpi`** — только **function-pointer** MMIO внутри процесса QEMU (`uart_cosim_register_dpi_ops`), без подключения ModelSim по TCP.

---

## Переменные окружения

| `UART16550_COSIM` | Режим |
|-------------------|--------|
| не задано / `0` | Локальная модель UART только в QEMU (cosim выключен). |
| `1`, `socket` или другое ≠ `dpi` | QEMU подключается к **`127.0.0.1:1234`** и обменивается строками `W`/`R` с ModelSim bridge. |
| `dpi` | Колбэки DPI в том же процессе; если ops не заданы — автоматический fallback на встроенную модель. |

**`UART_COSIM_LOG`**: `0` — тихо; `1` — по умолчанию (меньше логов по чтению LSR `0x14`); `2` — все смещения. Влияет на QEMU (`[COSIM]`) и на bridge (`[BRIDGE]`).

Проверка парсера протокола на хосте (без QEMU/ModelSim):

```bash
cd /home/vboxuser/diplom/qemu2/tests/rtl/uart_16550
make -f Makefile.bridgetest check-protocol
```

---

## Зависимости

- Собранный **`qemu-system-arm`** из `qemu2/build`.
- Образы Buildroot: `zImage`, `vexpress-v2p-ca9.dtb`, `rootfs.ext2`.
- ModelSim / Questa с DPI и **32-bit** сборкой `bridge_dpi.so`, если vsim 32-bit:

```bash
sudo dpkg --add-architecture i386
sudo apt update
sudo apt install -y gcc-multilib g++-multilib libc6-dev-i386
```

---

## Сборка QEMU

```bash
cd /home/vboxuser/diplom/qemu2/build
ninja qemu-system-arm
```

---

## Запуск полной косимуляции (порядок обязателен)

### Шаг 1 — терминал A: ModelSim + RTL + bridge

```bash
cd /home/vboxuser/diplom/qemu2/tests/rtl/uart_16550
/path/to/vsim -c -do run_cosim.do
```

Дождитесь строк **`[BRIDGE] waiting for QEMU on 127.0.0.1:1234...`**. Симулятор блокируется на **`accept`** до подключения QEMU.

### Шаг 2 — терминал B: QEMU + cosim + гость

```bash
cd /home/vboxuser/diplom && UART16550_COSIM=1 UART_COSIM_LOG=1 \
  bash qemu2/scripts/run_uart16550_qemu_telnet.sh
```

Используйте **`&&`** между `cd` и переменными, не склеивайте путь с `UART16550_COSIM=...`.

В терминале A должно появиться **`[BRIDGE] QEMU connected`**, в B — **`[COSIM socket] connected to 127.0.0.1:1234`**.

Гость использует MMIO по **0xff210000**; при включённом socket‑режиме транзакции обслуживает **RTL** через bridge.

### Шаг 3 — в госте: модуль и тест

На **хосте** перед запуском QEMU соберите **ARM** `.ko` и тест (в каталоге 9p не должно быть x86-бинарника):

```bash
cd /home/vboxuser/diplom/qemu2/drivers/uart16550_extended
make guest
```

При другом пути Buildroot задайте `BR_HOST`, `BR_KDIR`, `BR_CROSS` (см. `Makefile`).

В **госте** сначала **создайте точку монтирования и смонтируйте 9p** (одной строкой). Только `remount` без этого **не покажет файлы** с хоста.

```sh
mkdir -p /mnt/host
mount -t 9p -o trans=virtio hostshare /mnt/host
ls -la /mnt/host
```

`insmod` **строго одной строкой** (не разрывать `debug_level=2`):

```sh
insmod /mnt/host/uart16550_demo.ko base_addr=0xff210000 loopback=1 debug_level=2
chmod +x /mnt/host/test_uart16550_demo
/mnt/host/test_uart16550_demo --verbose --cosim
```

Каталог хоста задаётся в скрипте (`HOSTSHARE_DIR`, по умолчанию `drivers/uart16550_extended`).

---

## Локальный RTL-тест без QEMU

Без **`+COSIM`** тестбенч сам выполняет APB-сценарий (`run_all.do` и т.д.). С **`+COSIM`** симуляция ждёт QEMU: **`bridge_init`** делает **`accept`** на порту 1234, затем в цикле вызывается **`bridge_poll_once`** для приёма строк от QEMU.

---

## Режим DPI без TCP

Для одного процесса (свой бинарник + Verilator и т.п.):

```bash
cd /home/vboxuser/diplom && UART16550_COSIM=dpi bash qemu2/scripts/run_uart16550_qemu_telnet.sh
```

Пример клея: `tests/rtl/uart_16550/dpi_cosim_glue_example.c`.

---

## Типичные проблемы

| Симптом | Действие |
|---------|----------|
| `[COSIM socket] connect failed` | Сначала **`run_cosim.do`**, затем QEMU; проверьте, что порт 1234 свободен на localhost. |
| QEMU стартовал первым | Остановите QEMU и запустите снова после сообщения bridge про ожидание. |
| Нет логов MMIO | **`UART_COSIM_LOG=1`** или `2`. |
| Ошибка multilib при сборке `bridge_dpi.so` | Установите пакеты i386/multilib (см. выше). |

---

## Файлы

| Путь | Роль |
|------|------|
| `hw/char/uart_cosim_socket.c` | TCP-клиент, протокол строк |
| `hw/char/uart_cosim_dpi.c` | Колбэки DPI |
| `hw/char/uart_cosim_core.c` | Выбор socket / dpi по env |
| `hw/char/uart_stub.c` | MMIO устройство; fallback ops только для **`dpi`** |
| `tests/rtl/uart_16550/bridge_dpi.cpp` | Сервер `:1234`, вызов **`sv_uart_*`** |
| `tests/rtl/uart_16550/run_cosim.do` | Сборка **`bridge_dpi.so`** + **`vsim`** |
| `tests/rtl/uart_16550/tb_apb_uart.v` | DPI + **`bridge_poll_once`** на каждом такте в режиме COSIM |

Дополнительно: **`README_uart16550_rtl.md`**, **`UART16550_QEMU_INTERFACE.txt`**.
