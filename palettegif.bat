@echo off
setlocal enabledelayedexpansion

REM Set initial values
set "initial_fps=20"
set "fps=%initial_fps%"
set "initial_target_size_mb=15"
set "target_size_mb=%initial_target_size_mb%"
set "min_height=40"
set "max_tries=10"
set "start_time=0.000"
set "duration="

REM Get input file
set "input_file=%~1"

REM Exit if no input file is specified
if "%input_file%"=="" (
    echo No input file specified.
    pause
    exit /b 1
)

REM Get and display video information
echo ========== Video Information ==========
REM Get video duration
for /f "tokens=1,2" %%a in ('ffprobe -v error -show_entries format^=duration -of default^=noprint_wrappers^=1:nokey^=1 "%input_file%"') do (
    set "total_duration=%%a"
)

REM Get resolution, fps, and color space
for /f "tokens=*" %%a in ('ffprobe -v error -select_streams v:0 -show_entries "stream=width,height,r_frame_rate,nb_frames,pix_fmt" -of csv^=s^=x:p^=0 "%input_file%"') do (
    for /f "tokens=1-5 delims=x," %%b in ("%%a") do (
        set "original_width=%%b"
        set "original_height=%%c"
        set "colorspace=%%d"
        set "source_fps_raw=%%e"
        set "frame_count=%%f"
    )
)

REM Calculate actual FPS from fraction
for /f "tokens=1,2 delims=/" %%a in ("!source_fps_raw!") do (
    set /a "source_fps_num=%%a"
    set /a "source_fps_den=%%b"
    set /a "source_fps=!source_fps_num! / !source_fps_den!"
)

REM Calculate frame count if not available
if "!frame_count!"=="" (
    set /a "frame_count=!source_fps! * !total_duration!"
)

REM Display video information
echo Input file: %input_file%
echo Resolution: %original_width%x%original_height%
echo Duration: %total_duration% seconds
echo Frame count: %frame_count% frames
echo Color space: %colorspace%
echo Source FPS: %source_fps% ^(%source_fps_raw%^)
echo =====================================
echo.

REM Check if height information was retrieved
if not defined original_height (
    echo The input file is not a supported video format or height information couldnt be retrieved.
    pause
    exit /b 1
)

REM Display initial start time and accept input
:input_start_time
set /p "start_time=start time (seconds, up to 3 decimal places, 0-%total_duration%)=%start_time% or start time=" <nul
set /p "start_time="
if "%start_time%"=="" set "start_time=0.000"

set "invalid_char="
for /f "delims=0123456789." %%a in ("%start_time%") do set "invalid_char=%%a"
if defined invalid_char (
    set "start_time=0.000"
    echo Invalid character in start time. Please use numbers and decimal point only.
    goto input_start_time
)

set "temp_start=%start_time%"
set "decimal_count=0"
:count_decimals_start
if "!temp_start:~0,1!"=="." (
    set /a "decimal_count+=1"
)
if not "!temp_start!"=="" (
    set "temp_start=!temp_start:~1!"
    goto count_decimals_start
)
if %decimal_count% GTR 1 (
    echo Too many decimal points in start time.
    goto input_start_time
)

if not "!start_time:~-4,1!"=="." (
    if not "!start_time:~-3,1!"=="." (
        if not "!start_time:~-2,1!"=="." (
            if not "!start_time:~-1,1!"=="." (
                set "start_time=!start_time!.000"
            ) else (
                set "start_time=!start_time!000"
            )
        ) else (
            set "start_time=!start_time!00"
        )
    ) else (
        set "start_time=!start_time!0"
    )
)

set /a "start_time_int=start_time"
set /a "total_duration_int=total_duration"
if !start_time_int! GEQ !total_duration_int! (
    echo Start time ^(!start_time!^) must be less than video length ^(!total_duration! seconds^).
    set "start_time=0.000"
    goto input_start_time
)

REM Display duration input and validate
:input_duration
set /p "duration=duration (seconds, up to 3 decimal places, leave empty for full length)=" <nul
set /p "duration="
if not "%duration%"=="" (
    set "invalid_char="
    for /f "delims=0123456789." %%a in ("%duration%") do set "invalid_char=%%a"
    if defined invalid_char (
        echo Invalid character in duration. Please use numbers and decimal point only.
        set "duration="
        goto input_duration
    )

    set "temp_duration=%duration%"
    set "decimal_count=0"
    :count_decimals_duration
    if "!temp_duration:~0,1!"=="." (
        set /a "decimal_count+=1"
    )
    if not "!temp_duration!"=="" (
        set "temp_duration=!temp_duration:~1!"
        goto count_decimals_duration
    )
    if %decimal_count% GTR 1 (
        echo Too many decimal points in duration.
        set "duration="
        goto input_duration
    )

    if not "!duration:~-4,1!"=="." (
        if not "!duration:~-3,1!"=="." (
            if not "!duration:~-2,1!"=="." (
                if not "!duration:~-1,1!"=="." (
                    set "duration=!duration!.000"
                ) else (
                    set "duration=!duration!000"
                )
            ) else (
                set "duration=!duration!00"
            )
        ) else (
            set "duration=!duration!0"
        )
    )

    set /a "duration_int=duration"
    if !duration_int! GTR !total_duration_int! (
        echo Duration exceeds video length ^(!total_duration! seconds^).
        set "duration="
        goto input_duration
    )

    set /a "end_time=start_time_int + duration_int"
    if !end_time! GTR !total_duration_int! (
        echo Start time ^(!start_time!^) plus duration ^(!duration!^) exceeds video length ^(!total_duration! seconds^).
        set "duration="
        goto input_duration
    )
)

REM Display initial FPS and accept input
:input_fps
echo Source FPS: %source_fps%
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
echo Current resolution: %original_width%x%original_height%
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

REM Prepare time trim parameters
set "trim_params=-ss %start_time%"
if not "%duration%"=="" (
    set "trim_params=!trim_params! -t %duration%"
)

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
echo Time parameters: Start=%start_time%s Duration=%duration%s

REM Generate palette
ffmpeg -y -v warning -stats %trim_params% -i "%input_file%" -vf "fps=%fps%,scale=-1:!current_height!:flags=spline,palettegen" -update 1 -frames:v 1 "%palette_file%"
if errorlevel 1 (
    echo Error occurred while generating palette.
    if exist "%palette_file%" del "%palette_file%"
    pause
    exit /b 1
)

REM Generate GIF
ffmpeg -y -v warning -stats %trim_params% -i "%input_file%" -i "%palette_file%" -filter_complex "[0:v] fps=%fps%,scale=-1:!current_height!:flags=spline [x]; [x][1:v] paletteuse" -c:v gif "%output_file%"
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
REM Notify completion and display final information
if exist "%output_file%" (
    echo.
    echo ========== Conversion Complete ==========
    echo Input: %input_file%
    echo Output: %output_file%
    echo Original resolution: %original_width%x%original_height%
    echo Final height: !current_height!
    echo Original duration: %total_duration% seconds
    if not "%duration%"=="" echo Trimmed duration: %duration% seconds
    echo Source FPS: %source_fps%
    echo Output FPS: %fps%
    echo Output file size: %filesize% bytes ^(%target_size% bytes target^)
    echo Total tries: %tries%
    echo ====================================
) else (
    echo No output file generated due to maximum tries reached.
)

pause
endlocal