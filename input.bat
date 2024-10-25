@echo off
setlocal enabledelayedexpansion

REM Set initial values
set "initial_fps=20"
set "fps=%initial_fps%"
set "initial_target_size_mb=15"
set "target_size_mb=%initial_target_size_mb%"
set "min_height=40"
set "max_tries=10"

REM Get input file
set "input_file=%~1"

REM Exit if no input file is specified
if "%input_file%"=="" (
    echo No input file specified.
    pause
    exit /b 1
)

REM Check the input file and get its height
for /f "tokens=1,2" %%a in ('ffprobe -v error -select_streams v:0 -show_entries stream^=height -of csv^=s^=x:p^=0 "%input_file%"') do (
    set "original_height=%%a"
)

if not defined original_height (
    echo The input file is not a supported video format or height information couldnt be retrieved.
    pause
    exit /b 1
)

REM Display initial FPS and accept input
:input_fps
set /p "fps=fps=%fps% or fps=" <nul
set /p "fps="
if "%fps%"=="" set "fps=%initial_fps%"
set "non_numeric="
for /f "delims=0123456789" %%a in ("%fps%") do set "non_numeric=%%a"
if defined non_numeric (
    set "fps=%initial_fps%"
    echo Please enter a valid FPS.
    goto input_fps
)

REM Display initial height and accept input
:input_height
set /p "height=height=%original_height% or height=" <nul
set /p "height="
if "%height%"=="" set "height=%original_height%"
set "non_numeric="
for /f "delims=0123456789" %%a in ("%height%") do set "non_numeric=%%a"
if defined non_numeric (
    set "height=%original_height%"
    echo Please enter a valid height.
    goto input_height
)

REM Display initial target size and accept input
:input_size
set /p "target_size_mb=size=%target_size_mb%mb or size=" <nul
set /p "target_size_mb="
if "%target_size_mb%"=="" set "target_size_mb=%initial_target_size_mb%"
set "non_numeric="
for /f "delims=0123456789" %%a in ("%target_size_mb%") do set "non_numeric=%%a"
if defined non_numeric (
    set "target_size_mb=%initial_target_size_mb%"
    echo Please enter a valid size in MB.
    goto input_size
)

REM Calculate target size in bytes
set /a "target_size=%target_size_mb% * 1024 * 1024"

REM Set output file name
set "output_file=%~dpn1.gif"

REM Initialize binary search variables
set /a "low_height=%min_height%"
set /a "high_height=%height%"
set "tries=0"

:generate_gif
REM Set temporary palette file name
set "palette_file=%~dpn1_palette.png"

REM Set current height for the first try
if %tries%==0 (
    set "current_height=%height%"
) else (
    set /a "current_height=(low_height + high_height) / 2"
)
set /a "tries+=1"

echo.
echo ========== Trial %tries% of %max_tries% ==========
echo Attempting with height: !current_height!

REM Generate palette
ffmpeg -y -v warning -stats -i "%input_file%" -vf "fps=%fps%,scale=-1:!current_height!:flags=spline,palettegen" -update 1 -frames:v 1 "%palette_file%"
if errorlevel 1 (
    echo Error occurred while generating palette.
    if exist "%palette_file%" del "%palette_file%"
    pause
    exit /b 1
)

REM Generate GIF
ffmpeg -y -v warning -stats -i "%input_file%" -i "%palette_file%" -filter_complex "[0:v] fps=%fps%,scale=-1:!current_height!:flags=spline [x]; [x][1:v] paletteuse" -c:v gif "%output_file%"
if errorlevel 1 (
    echo Error occurred while generating GIF.
    if exist "%palette_file%" del "%palette_file%"
    pause
    exit /b 1
)

REM Get output file size
for %%I in ("%output_file%") do set "filesize=%%~zI"

echo Trial %tries%: Current file size: !filesize! bytes

REM Delete temporary palette file
if exist "%palette_file%" del "%palette_file%"

REM Size check and binary search
if !filesize! GTR %target_size% (
    if !tries!==1 (
        echo.
        echo File size exceeds target size.
        echo Starting binary search to find optimal height for target file size...
        echo.
    )
    if !tries! GEQ %max_tries% (
        echo Maximum tries reached. Deleting output file.
        if exist "%output_file%" del "%output_file%"
        goto end
    )
    if !current_height! LEQ %min_height% (
        echo Reached minimum height. Best attempt: !filesize! bytes
        goto end
    )
    set /a "high_height=current_height - 1"
    goto generate_gif
) else (
    set /a "size_diff=target_size - filesize"
    if !size_diff! LSS 1048576 (
        echo Target size achieved within 1MB tolerance. File size: !filesize! bytes
        goto end
    )
    if %tries%==1 (
        echo First try successful. File size: !filesize! bytes
        goto end
    )
    set /a "low_height=current_height + 1"
    goto generate_gif
)

:end
REM Notify completion
if exist "%output_file%" (
    echo Conversion completed: %output_file%
    echo Output file size: %filesize% bytes
) else (
    echo No output file generated due to maximum tries reached.
)
echo Total tries: %tries%
echo Last attempted height: !current_height!
pause
endlocal