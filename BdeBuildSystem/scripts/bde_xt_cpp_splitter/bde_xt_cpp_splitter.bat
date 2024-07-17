@echo off
set mydir=%~dp0
setlocal
  set PYTHONPATH=%PYTHONPATH%:%mydir%
  python %~dp0/bde_xt_cpp_splitter.py %*
endlocal
