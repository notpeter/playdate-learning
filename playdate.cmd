@echo off
set PLAYDATE_SDK_PATH=%USERPROFILE%\Documents\PlaydateSDK
set PDC=%PLAYDATE_SDK_PATH%\bin\pdc
set SIM=%PLAYDATE_SDK_PATH%\bin\PlaydateSimulator.exe

%PDC% . play.pdx
%SIM% play.pdx
