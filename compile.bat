@echo off
cls
@REM odin build . -out:toml_parser.exe -o:none -debug && toml_parser.exe
odin run . -debug 
