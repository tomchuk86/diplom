# После compile.do: do run.do   (GUI: окно остаётся, можно Wave; GTKWave смотрит waves_uart.vcd)
# -onfinish stop — не выходить из ModelSim при $finish (exit закрывал бы прогу).
# Закрыть вручную: меню File -> Quit, или в Transcript: quit -f
if {[file exists sim_transcript.log]} { file delete -force sim_transcript.log }
transcript file sim_transcript.log
transcript on
echo "Transcript: [file normalize [pwd]/sim_transcript.log]"
vsim -onfinish stop work.tb_apb_uart
onbreak {resume}
do wave_add.do
run -all
echo "Готово. View->Wave — кривые уже добавлены. GTKWave: waves_uart.vcd в этой папке"
# quit -f
