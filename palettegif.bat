@echo off
setlocal enabledelayedexpansion

set "initial_fps=20"
set "fps=%initial_fps%"
set "initial_target_size_mb=15"
set "target_size_mb=%initial_target_size_mb%"
set "min_height=40"
set "max_tries=10"
set "start_time=0"
set "duration="

set "input_file=%~1"

if "%input_file%"=="" (
    echo No input file specified.
    pause
    exit /b 1
)

for /f "tokens=1,2 delims=." %%a in ('ffprobe -v error -show_entries format^=duration -of default^=noprint_wrappers^=1:nokey^=1 "%input_file%"') do (
    set "total_duration_int=%%a"
    set "total_duration=%%a.%%b"
    set /a "total_minutes=%%a/60"
    set /a "total_seconds=%%a%%60"
)

for /f "tokens=*" %%a in ('ffprobe -v error -select_streams v:0 -show_entries "stream=width,height,r_frame_rate,nb_frames,pix_fmt" -of csv^=s^=x:p^=0 "%input_file%"') do (
    for /f "tokens=1-5 delims=x," %%b in ("%%a") do (
        set "original_width=%%b"
        set "original_height=%%c"
        set "colorspace=%%d"
        set "source_fps_raw=%%e"
        set "frame_count=%%f"
    )
)

for /f "tokens=1,2 delims=/" %%a in ("!source_fps_raw!") do (
    set /a "source_fps_num=%%a"
    set /a "source_fps_den=%%b"
    set /a "source_fps=!source_fps_num! / !source_fps_den!"
)

if "!frame_count!"=="" (
    set /a "frame_count=!source_fps! * !total_duration_int!"
)

set "padded_total_seconds=0!total_seconds!"
set "padded_total_seconds=!padded_total_seconds:~-2!"

echo Input file: %input_file%
echo Resolution: %original_width%x%original_height%
echo Duration: %total_minutes%:!padded_total_seconds! ^(Total: %total_duration% seconds^)
echo Frame count: %frame_count% frames
echo Color space: %colorspace%
echo Source FPS: %source_fps% ^(%source_fps_raw%^)
echo =====================================
echo.

:main_input_loop
set "start_time=0"
set "duration="
call :update_timeline

:input_start_time
set /p "start_time_input=Start time (mm:ss or seconds, max %total_minutes%:!padded_total_seconds!)=" || set "start_time_input="
if "%start_time_input%"=="" (
    set "start_time=0"
    goto check_start_time
)

echo.%start_time_input%| findstr /r "^[0-9][0-9]*:[0-9][0-9]*$" >nul
if !errorlevel! equ 0 (
    for /f "tokens=1,2 delims=:" %%a in ("%start_time_input%") do (
        set /a "temp_sec=%%b"
        if !temp_sec! GEQ 60 (
            echo Invalid seconds value. Seconds must be less than 60.
            goto input_start_time
        )
        set /a "start_time=%%a * 60 + %%b"
    )
) else (
    echo.%start_time_input%| findstr /r "^[0-9][0-9]*$" >nul
    if !errorlevel! equ 0 (
        set "start_time=%start_time_input%"
    ) else (
        echo Invalid format. Please use either:
        echo  - mm:ss format ^(e.g. 1:30, 0:45^)
        echo  - seconds only ^(e.g. 90, 45^)
        goto input_start_time
    )
)

:check_start_time
if !start_time! GEQ !total_duration_int! (
    echo Start time ^(!start_time! seconds^) must be less than video length ^(!total_duration! seconds^).
    goto input_start_time
)

call :update_timeline

:input_duration
set /p "duration_input=Duration (mm:ss or seconds, leave empty for full length)=" || set "duration_input="
if "%duration_input%"=="" (
    set "duration="
    goto confirm_range
)

echo.%duration_input%| findstr /r "^[0-9][0-9]*:[0-9][0-9]*$" >nul
if !errorlevel! equ 0 (
    for /f "tokens=1,2 delims=:" %%a in ("%duration_input%") do (
        set /a "temp_sec=%%b"
        if !temp_sec! GEQ 60 (
            echo Invalid seconds value. Seconds must be less than 60.
            goto input_duration
        )
        set /a "duration=%%a * 60 + %%b"
    )
) else (
    echo.%duration_input%| findstr /r "^[0-9][0-9]*$" >nul
    if !errorlevel! equ 0 (
        set "duration=%duration_input%"
    ) else (
        echo Invalid format. Please use either:
        echo  - mm:ss format ^(e.g. 1:30, 0:45^)
        echo  - seconds only ^(e.g. 90, 45^)
        goto input_duration
    )
)

set /a "end_time=%start_time% + %duration%"
if !end_time! GTR !total_duration_int! (
    echo Duration is too long. Maximum duration from start point is !total_duration_int! seconds.
    set "duration="
    goto input_duration
)

:confirm_range
call :update_timeline
set /p "confirm=Is this range correct? (y/n): "
if /i "!confirm!"=="y" (
    goto input_fps
) else if /i "!confirm!"=="n" (
    goto main_input_loop
) else (
    goto confirm_range
)

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

goto start_conversion

:update_timeline
set "timeline_width=50"
set "timeline="
for /l %%i in (0,1,%timeline_width%) do (
    set /a "current_pos=%%i * total_duration_int / timeline_width"
    if !current_pos! GEQ !start_time! (
        if defined duration (
            set /a "end_time=start_time + duration"
            if !current_pos! LSS !end_time! (
                set "timeline=!timeline!#"
            ) else (
                set "timeline=!timeline!-"
            )
        ) else (
            set "timeline=!timeline!#"
        )
    ) else (
        set "timeline=!timeline!-"
    )
)

set /a "start_minutes=start_time / 60"
set /a "start_seconds=start_time %% 60"
set "padded_start_seconds=0!start_seconds!"
set "padded_start_seconds=!padded_start_seconds:~-2!"

echo.
echo Video Timeline
echo [!timeline!]
echo.

if "!duration!"=="" (
    echo Selected: !start_minutes!:!padded_start_seconds! - Full length
) else (
    set /a "end_time=start_time + duration"
    set /a "end_minutes=end_time / 60"
    set /a "end_seconds=end_time %% 60"
    set "padded_end_seconds=0!end_seconds!"
    set "padded_end_seconds=!padded_end_seconds:~-2!"
    
    set /a "duration_minutes=duration / 60"
    set /a "duration_seconds=duration %% 60"
    set "padded_duration_seconds=0!duration_seconds!"
    set "padded_duration_seconds=!padded_duration_seconds:~-2!"
    
    echo Selected: !start_minutes!:!padded_start_seconds! - !end_minutes!:!padded_end_seconds! ^(Duration: !duration_minutes!:!padded_duration_seconds!^)
)
echo.
exit /b

:start_conversion
set /a "target_size=%target_size_mb% * 1024 * 1024"
set "output_file=%~dpn1.gif"
set /a "low_height=%min_height%"
set /a "high_height=%height%"
set "tries=0"

set "trim_params=-ss %start_time%"
if not "%duration%"=="" (
    set "trim_params=!trim_params! -t %duration%"
)

:generate_gif
set "palette_file=%~dpn1_palette.png"

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

ffmpeg -y -v warning -stats %trim_params% -i "%input_file%" -vf "fps=%fps%,scale=-1:!current_height!:flags=spline,palettegen" -update 1 -frames:v 1 "%palette_file%"
if errorlevel 1 (
    echo Error occurred while generating palette.
    if exist "%palette_file%" del "%palette_file%"
    pause
    exit /b 1
)

ffmpeg -y -v warning -stats %trim_params% -i "%input_file%" -i "%palette_file%" -filter_complex "[0:v] fps=%fps%,scale=-1:!current_height!:flags=spline [x]; [x][1:v] paletteuse" -c:v gif "%output_file%"
if errorlevel 1 (
    echo Error occurred while generating GIF.
    if exist "%palette_file%" del "%palette_file%"
    pause
    exit /b 1
)

for %%I in ("%output_file%") do set "filesize=%%~zI"

echo Trial %tries%: Current file size: !filesize! bytes

if exist "%palette_file%" del "%palette_file%"

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