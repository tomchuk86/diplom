# Запуск цепочки: RTL (ModelSim) — bridge — QEMU — Buildroot — драйвер

Проект: косимуляция UART 16550 между **QEMU** (`uart-stub` + сокет), **DPI-bridge** (`bridge_dpi.cpp`) и **RTL** (`apb_uart_16550` / `uart_16550_core`).

## Зависимости (хост, Linux)

- Собранный **QEMU** из этого дерева: `ninja -C build qemu-system-arm`
- **ModelSim** Intel FPGA Edition (у вас может быть путь вида `/root/intelFPGA/20.1/modelsim_ase/linuxaloem/vsim`)
- **i386** библиотеки и multilib для DPI (32-bit vsim):
  ```bash
  sudo dpkg --add-architecture i386
  sudo apt update
  sudo apt install -y gcc-multilib g++-multilib libc6-dev-i386
  ```
- **Buildroot** с собранными образами, пути ниже — пример для типичной сборки:
  - `zImage`, `vexpress-v2p-ca9.dtb`, `rootfs.ext2` в `~/buildroot/output/images/`

## Порядок запуска (важно)

1. Сначала **ModelSim + bridge** (слушает TCP `127.0.0.1:1234`).
2. Затем **QEMU** (подключается к bridge как клиент).
3. В госте **insmod** драйвера и тест.

---

## 1. Остановить старые процессы

```bash
pkill -f qemu-system-arm
pkill -f vsim
```

---

## 2. Собрать драйвер и userspace-тест (на хосте)

```bash
cd /path/to/qemu/drivers/uart16550_demo
make clean
make
```

При ошибках заголовков ядра один раз:

```bash
make -C /path/to/buildroot/output/build/linux-VERSION \
  ARCH=arm \
  CROSS_COMPILE=/path/to/buildroot/output/host/bin/arm-none-linux-gnueabihf- \
  modules_prepare
```

(подставьте свой `linux-VERSION` и путь к toolchain из Buildroot)

---

## 3. Терминал A — RTL + DPI bridge

```bash
cd /path/to/qemu/tests/rtl/uart_16550
sudo /path/to/modelsim_ase/linuxaloem/vsim -c -do run_cosim.do
```

Ожидаемые строки: `COSIM mode enabled`, `[BRIDGE] waiting for connection...`, после старта QEMU — `[BRIDGE] connected`.

Окно не закрывать. **Не нажимать Ctrl+C** в ModelSim без нужды (симуляция встанет на паузу).

---

## 4. Терминал B — QEMU + vexpress-a9 + Buildroot + каталог с драйвером по 9p

Рекомендуемый запуск через проектный скрипт. Консоль Linux выводится не в окно
QEMU, а в telnet-порт `5555`, чтобы к ней можно было подключиться с
хоста/Windows:

```bash
bash /home/vboxuser/qemu/scripts/run_uart16550_qemu_telnet.sh
```

По умолчанию скрипт использует:

- QEMU: `/home/vboxuser/qemu/build/qemu-system-arm`
- Buildroot images: `/home/vboxuser/buildroot/output/images`
- hostshare: `/home/vboxuser/qemu/drivers/uart16550_demo`
- telnet console: `0.0.0.0:5555`

При необходимости пути можно переопределить переменными окружения:

```bash
QEMU_BIN=/path/to/qemu-system-arm \
BUILDROOT_IMAGES=/path/to/buildroot/output/images \
HOSTSHARE_DIR=/path/to/qemu/drivers/uart16550_demo \
TELNET_PORT=5555 \
bash /home/vboxuser/qemu/scripts/run_uart16550_qemu_telnet.sh
```

Эквивалентная ручная команда:

```bash
/path/to/qemu/build/qemu-system-arm \
  -M vexpress-a9 \
  -m 256M \
  -kernel /path/to/buildroot/output/images/zImage \
  -dtb /path/to/buildroot/output/images/vexpress-v2p-ca9.dtb \
  -drive if=sd,file=/path/to/buildroot/output/images/rootfs.ext2,format=raw \
  -append "console=ttyAMA0,115200 root=/dev/mmcblk0 rootwait rootfstype=ext4 rw" \
  -fsdev local,id=fsdev0,path=/path/to/qemu/drivers/uart16550_demo,security_model=none \
  -device virtio-9p-device,fsdev=fsdev0,mount_tag=hostshare \
  -display none \
  -monitor none \
  -serial telnet:0.0.0.0:5555,server,nowait
```

Почему не `-virtfs`: на `vexpress-a9` нет PCI, используется **virtio-9p-device** (MMIO).

Подключение к консоли Linux в QEMU:

- с той же Linux-машины:
  ```bash
  telnet 127.0.0.1 5555
  ```
- с Windows-хоста через PuTTY:
  - Connection type: `Telnet`
  - Host Name: IP вашей VM
  - Port: `5555`

Если VM в VirtualBox работает в режиме **NAT**, Windows-хост может не видеть порт
гостевой Ubuntu напрямую. В этом случае добавьте в настройках VM проброс порта:

- `Settings` → `Network` → `Advanced` → `Port Forwarding`
- Host Port: `5555`
- Guest Port: `5555`

После этого в PuTTY на Windows подключайтесь к:

- Host Name: `127.0.0.1`
- Port: `5555`

Если нужно вернуть старое поведение, где консоль печатается прямо в терминал
запуска QEMU, замените последние три строки на `-nographic`.

---

## 5. В госте Buildroot (консоль QEMU, логин `root`)

```sh
mkdir -p /mnt/host
mount | grep hostshare || mount -t 9p -o trans=virtio hostshare /mnt/host
ls -l /mnt/host

rmmod uart16550_demo 2>/dev/null
insmod /mnt/host/uart16550_demo.ko base_addr=0x10014000

/mnt/host/test_uart16550_demo
```

База **0x10014000** — для платформы `vexpress-a9` с вашим UART в этой карте памяти (см. `README_uart16550_rtl.md`).

---

## 6. Признаки успешной работы

- В терминале A (bridge): строки `[BRIDGE] READ/WRITE ...` по мере работы гостя.
- В логе QEMU: `[COSIM] connected to bridge`, при чтении LSR — `read addr=0x5 (cosim=0x14)` (смещение APB для регистра LSR).
- В госте: вывод теста, в т.ч. `RX_TEST=PASS` и строка `TX=... RX=... ERR=... IRQ=...`.

---

## 7. Локальный RTL-тест без QEMU (только ModelSim)

Только самопроверка тестбенча, без сокета:

```bash
cd /path/to/qemu/tests/rtl/uart_16550
/path/to/vsim -c -do run_all.do
```

Результаты: `sim_result.txt`, `sim_transcript.log` (и при необходимости VCD).

---

## 8. Типичные проблемы

| Симптом | Что сделать |
|--------|-------------|
| `[COSIM] connect failed` | Сначала запустить ModelSim `run_cosim.do`, потом QEMU. |
| `vsim: ... export_tramp.so` / `crti.o` | Поставить `gcc-multilib`, `libc6-dev-i386` (см. зависимости). |
| Kernel panic `unknown-block(0,0)` | Добавить `rootwait rootfstype=ext4`, проверить путь к `rootfs.ext2` и `-drive`. |
| `/dev/uart16550_demo: No such file` | Выполнить `insmod ... base_addr=0x10014000`. |
| Тест `syntax error` при запуске | Пересобрать `test_uart16550_demo` через `Makefile` (кросс-компилятор arm из Buildroot). |

---

## 8. Файлы, относящиеся к цепочке

| Путь | Назначение |
|------|------------|
| `hw/char/uart_cosim_socket.c` | TCP-клиент QEMU → `127.0.0.1:1234` |
| `hw/char/uart_stub.c` | MMIO-модель UART, cosim-хуки |
| `tests/rtl/uart_16550/bridge_dpi.cpp` | DPI: сокет-сервер + вызов SV task |
| `tests/rtl/uart_16550/run_cosim.do` | Сборка `bridge_dpi.so` и запуск `+COSIM` |
| `rtl/uart_16550/*.v` | RTL UART + APB |
| `drivers/uart16550_demo/` | Демо-драйвер и `test_uart16550_demo` |

Подробнее по карте регистров и смещениям: `README_uart16550_rtl.md`, `UART16550_QEMU_INTERFACE.txt`.
