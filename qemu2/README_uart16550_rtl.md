# UART 16550A — RTL-проект (APB, Verilog)

Аппаратный **UART-контроллер** в духе стандарта **NS16550A**: передача/приём, делитель скорости (16×), 8-уровневые **FIFO** (TX/RX), регистровый набор, **прерывание** `intr`. Ведомый интерфейс шины **APB3** (при необходимости AXI4-Lite делается отдельной обёрткой с той же картой регистров).

**Инструменты:** Verilog, симуляция в **ModelSim** (в т.ч. Altera/Quartus 13.1 ASE), лог аналогично **Quartus** (файлы `.v`).

---

## Размещение в QEMU

| Путь | Назначение |
|------|------------|
| `rtl/uart_16550/` | Исходный RTL, подключаемый к дипломной части проекта |
| `tests/rtl/uart_16550/` | ModelSim-тестбенч и `*.do`-скрипты |
| `hw/char/uart_stub.c` | QEMU MMIO-модель UART 16550A / точка подключения co-sim |
| `hw/char/uart_cosim_socket.c` | TCP-клиент для bridge на `127.0.0.1:1234` |
| `hw/arm/uartarm_soc.c` | Минимальная машина `uartarm-soc` с UART по адресу `0xff210000` |
| `hw/arm/vexpress.c` | Рабочая Buildroot-платформа `vexpress-a9`; UART добавлен по адресу `0xff210000`, как на DE1-SoC через lightweight bridge |

## Состав исходного RTL-проекта

| Путь | Назначение |
|------|------------|
| `rtl/uart_16550/` | Исходный RTL |
| `tests/rtl/uart_16550/` | Тестбенч, `*.do` для ModelSim, результаты прогона |

### RTL-модули

| Файл | Кратко |
|------|--------|
| `uart_baud.v` | Бод-генератор: 16× оversampling, делитель `{DLH,DLL}` |
| `uart_fifo.v` | Синхронный FIFO (параметр глубины) |
| `uart_tx.v` / `uart_rx.v` | Линия UART: 5–8 бит, чётность, 1/2 stop |
| `uart_16550_core.v` | Регистры, IRQ, MCR.4=loopback, RBR/THR через FIFO |
| `apb_uart_16550.v` | Обёртка **APB**: `paddr[4:2]` → регистр 0..7, данные в `pwdata[7:0]` / `prdata[7:0]` |

### Симуляция (`tests/rtl/uart_16550/`)

| Файл | Назначение |
|------|------------|
| `tb_apb_uart.v` | Самотест: APB → настройка UART → `0xA5` в THR, loopback `rxd=txd` → чтение RBR |
| `compile.do` | `vlib` + `vlog` всех модулей |
| `run.do` | GUI: `vsim`, `wave_add`, прогон, окно **не** закрывается (`-onfinish stop`) |
| `run_all.do` | Всё в одной команде + `quit` (удобно для `vsim -c`) |
| `run_modelsim_from_cmd.cmd` | Пакетный запуск из cmd (нужен путь к `vsim.exe`) |
| `wave_add.do` | Готовый набор сигналов для окна **Wave** |

**Артефакты прогона (в `tests/rtl/uart_16550/`):**

- `sim_result.txt` — строка `RESULT=PASS` / `RESULT=FAIL` и байт RBR  
- `sim_transcript.log` — лог Transcript  
- `waves_uart.vcd` — VCD **только** для иерархии `dut.u` (для **GTKWave**; не путать со старыми гигабайтными VCD)

---

## Быстрый старт (ModelSim GUI)

1. `cd /home/vboxuser/diplom/qemu2/tests/rtl/uart_16550` (в Transcript или через меню).
2. `do compile.do`
3. `do run.do`
4. **View → Wave** — сигналы подставляются из `wave_add.do`.
5. **Zoom Full** в окне Wave, чтобы увидеть весь прогон.

**GTKWave:** открыть `tests/rtl/uart_16550/waves_uart.vcd`.

**Отключить VCD** при компиляции: добавь в `compile.do` к `vlog` флаг: `+define+NO_VCD`.

---

## Карта регистров (смещения в байтах, 16550-стиль)

| Offset | Read | Write (часто) | Примечание |
|--------|------|----------------|------------|
| `0x00` | RBR | THR / DLL при DLAB=1 | DLAB = `LCR[7]` |
| `0x04` | IER | IER / DLH при DLAB=1 | IER: биты 0..2 |
| `0x08` | IIR | FCR | |
| `0x0C` | LCR | LCR | 8N1, чётность, стоп, DLAB |
| `0x10` | MCR | MCR | bit4 = loopback (в реестре 5 бит) |
| `0x14` | LSR | — | data ready, THRE, ошибки |
| `0x18` | MSR* | — | в RTL упрощённо |
| `0x1C` | SCR | SCR | |

На APB: адрес слова = смещение, полезный байт — **младший** (`[7:0]`). Индекс регистра: `paddr[4:2] = 0..7`.

**Скорость:** `f_baud ≈ f_clk / (16 × {DLH,DLL})`; при 0 в делителе в `uart_baud` используется 1.

---

## Ограничения (для отчёта/защиты)

Реализация **упрощённая** относительно полного 16550A: IIR/приоритеты, modem-линии, часть FCR, RX timeout — не полный промышленный аналог. Для **AXI4-Lite** в СнК делается отдельный адаптер: та же **байтовая** карта `0x00`…`0x1C`.

---

## Синтез (Quartus / др.)

- Топ по APB: `apb_uart_16550` (тестбенч в проект **не** включать).  
- Назначить `pclk`, `presetn`, `paddr`, шины, `uart_txd` / `uart_rxd` на выводы/виртуальные пины.  
- Версия **Quartus II 13.1** + ModelSim ASE совместимы; при жёстких настройках Verilog-2001 и `$clog2` в `uart_fifo` смотрите варнинги компилятора.

---

## Лицензия / диплом

Код сгенерирован/собран в учебных целях; при оформлении работы укажите фактические ограничения и результаты симуляции (например, `sim_result.txt` и скриншоты волн).
