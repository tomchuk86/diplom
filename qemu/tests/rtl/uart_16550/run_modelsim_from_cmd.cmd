@echo off
chcp 65001 >nul
cd /d "%~dp0"
rem Подправь путь к vsim из своей установки Altera/Quartus:
set "VSIM=C:\altera\13.1\modelsim_ase\win32aloem\vsim.exe"
if not exist "%VSIM%" (
  echo Укажи VSIM=... к vsim.exe внутри run_modelsim_from_cmd.cmd
  echo Обычно: ...\modelsim_ase\win32aloem\vsim.exe
  pause
  exit /b 1
)
echo Запуск: "%VSIM%" -c -do run_all.do
"%VSIM%" -c -do run_all.do
echo.
echo Готово: sim_result.txt  sim_transcript.log  waves_uart.vcd
echo GTKWave: File -^> Open New Tab -^> выбрать waves_uart.vcd
if exist sim_result.txt type sim_result.txt
pause
