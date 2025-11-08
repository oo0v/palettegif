@echo off
setlocal enabledelayedexpansion

set "CONFIG_INITIAL_FPS=20"
set "CONFIG_INITIAL_TARGET_SIZE_MB=15"
set "CONFIG_MIN_HEIGHT=40"
set "CONFIG_MAX_TRIES=10"
set "CONFIG_TIMELINE_WIDTH=50"

set "fps=!CONFIG_INITIAL_FPS!"
set "target_size_mb=!CONFIG_INITIAL_TARGET_SIZE_MB!"
set "min_height=!CONFIG_MIN_HEIGHT!"
set "max_tries=!CONFIG_MAX_TRIES!"
    
set "start_min=0"
set "start_sec=0"
set "start_sec_decimal=0"
set "end_min=0"
set "end_sec=0"
set "end_sec_decimal=0"

set "input_file=%~1"
if "!input_file!"=="" (
    call :show_error "No input file specified."
    endlocal
    goto error_exit
)

call :get_video_info "!input_file!"
if errorlevel 1 goto error_exit

set "padded_total_seconds=0!total_seconds!"
set "padded_total_seconds=!padded_total_seconds:~-2!"
echo =====================================
echo Input file: !input_file!
echo Resolution: !original_width!x!original_height!
echo Duration: !total_minutes!:!padded_total_seconds!.!total_seconds_decimal:~0,3!
echo Frame count: !frame_count! frames
echo Source FPS: !source_fps! (!source_fps_raw!)
echo =====================================
echo.

:ask_time_range
echo Do you want to specify time range? (Default: Full video)
set /p "specify_time=y/n: "
echo.

if /i "!specify_time!"=="y" (
    call :get_time_range
    if errorlevel 1 goto error_exit
) else if /i "!specify_time!"=="n" (
    set "start_min=0"
    set "start_sec=0"
    set "start_sec_decimal=000"

    set "end_min=!total_minutes!"
    set "end_sec=!total_seconds!"
    set "end_sec_decimal=!total_seconds_decimal:~0,3!"

    set "start_time=0:00.000"
    set "end_time=!total_minutes!:!padded_total_seconds!.!end_sec_decimal:~0,3!"

    call :calculate_duration
    if errorlevel 1 goto error_exit

    echo Using full video length:
    echo Start: !start_time!
    echo End: !end_time!
    echo Duration: !duration!
    echo.
) else (
    echo Please enter 'y' or 'n'
    echo.
    goto ask_time_range
)

set "output_file=%~dpn1.gif"

:conversion_start
call :get_conversion_parameters
if errorlevel 1 goto error_exit

:confirm_conversion
echo.
set /p "confirm=Start conversion? (y/n): "
if /i "!confirm!"=="n" (
    echo.
    echo Restarting parameter input...
    echo.
    goto conversion_start
)
if /i "!confirm!"=="y" (
    call :process_gif
    if errorlevel 1 goto error_exit

    call :display_results
    endlocal
    goto end_script
)
echo Please enter 'y' or 'n'
goto confirm_conversion

:error_exit
    endlocal
    pause
    exit /b 1

:end_script
    if exist "!palette_file!" del "!palette_file!"
    pause
    exit /b 0

:get_video_info
    set "video_file=%~1"

    for /f "usebackq tokens=1,2 delims=." %%a in (`ffprobe -v error -show_entries format^=duration -of default^=noprint_wrappers^=1:nokey^=1 "%video_file%"`) do (
        set "total_duration_int=%%a"
        set "total_seconds_decimal=%%b"
    )

    if not defined total_duration_int (
        call :show_error "Could not read duration."
        exit /b 1
    )
    if not defined total_seconds_decimal set "total_seconds_decimal=000"

    set /a "total_minutes=total_duration_int / 60"
    set /a "total_seconds=total_duration_int %% 60"

    for /f "usebackq delims=" %%a in (`
        ffprobe -v error -select_streams v:0 -show_entries stream^=width -of default^=noprint_wrappers^=1:nokey^=1 "%video_file%"
    `) do set "original_width=%%a"

    for /f "usebackq delims=" %%a in (`
        ffprobe -v error -select_streams v:0 -show_entries stream^=height -of default^=noprint_wrappers^=1:nokey^=1 "%video_file%"
    `) do set "original_height=%%a"

    for /f "usebackq delims=" %%a in (`
        ffprobe -v error -select_streams v:0 -show_entries stream^=r_frame_rate -of default^=noprint_wrappers^=1:nokey^=1 "%video_file%"
    `) do set "source_fps_raw=%%a"

    for /f "usebackq delims=" %%a in (`
        ffprobe -v error -select_streams v:0 -show_entries stream^=nb_frames -of default^=noprint_wrappers^=1:nokey^=1 "%video_file%"
    `) do set "frame_count=%%a"

    for /f "usebackq delims=" %%a in (`
        ffprobe -v error -select_streams v:0 -show_entries stream^=pix_fmt -of default^=noprint_wrappers^=1:nokey^=1 "%video_file%"
    `) do set "pix_fmt=%%a"

    set "source_fps=0"
    if defined source_fps_raw (
        for /f "tokens=1,2 delims=/" %%a in ("!source_fps_raw!") do (
            set "source_fps_num=%%a"
            set "source_fps_den=%%b"
        )

        if not defined source_fps_den (
            set "source_fps=!source_fps_num!"
        ) else (
            if "!source_fps_den!"=="0" (
                set "source_fps=!source_fps_num!"
            ) else (
                set /a "source_fps=!source_fps_num! / !source_fps_den!"
            )
        )
    )

    if /I "!frame_count!"=="N/A" set "frame_count="
    if not defined frame_count (
        set /a "frame_count=!source_fps! * !total_duration_int!"
    )

exit /b 0

:get_time_range
    :time_input_loop
    call :get_start_time
    if errorlevel 1 goto time_input_loop

    :end_time_loop
    call :get_end_time
    if errorlevel 1 goto end_time_loop

    call :calculate_duration
    if errorlevel 1 (
        echo Press Enter to retry time input...
        echo.
        pause > nul
        goto time_input_loop
    )

    call :confirm_time_range
    if errorlevel 1 goto time_input_loop
exit /b 0

:get_start_time
    echo Maximum time is !total_minutes!:!padded_total_seconds!.!total_seconds_decimal:~0,3!
    echo Press Enter without input to start from beginning (0:00.000)
    echo.
    
    :start_time_input_loop
    set "start_min=0"
    set "start_sec=0"
    set "start_sec_decimal=000"

    set /p "temp_input=Start minutes (0-!total_minutes!): "
    if "!temp_input!"=="" (
        echo 0
    ) else (
        if !temp_input! GTR !total_minutes! (
            echo Error: Minutes must be between 0 and !total_minutes!.
            goto start_time_input_loop
        )
        set "start_min=!temp_input!"
    )
    
    set /p "temp_input=Start seconds (0-59): "
    if "!temp_input!"=="" (
        echo 0
    ) else (
        if !temp_input! GEQ 60 (
            echo Error: Seconds must be between 0 and 59.
            goto start_time_input_loop
        )
        set /a "total_start_seconds=!start_min! * 60 + !temp_input!"
        set /a "total_video_seconds=!total_minutes! * 60 + !total_seconds!"
        if !total_start_seconds! GTR !total_video_seconds! (
            echo Error: Start time exceeds video duration.
            goto start_time_input_loop
        )
        set "start_sec=!temp_input!"
    )
    
    set /p "temp_input=Start seconds decimal (0-999): "
    if "!temp_input!"=="" (
        set "start_sec_decimal=000"
    ) else (
        set "padded_decimal=00!temp_input!"
        set "padded_decimal=!padded_decimal:~-3!"
        if !start_min! EQU !total_minutes! if !start_sec! EQU !total_seconds! (
            if !temp_input! GTR !total_seconds_decimal! (
                echo Error: Start time exceeds video duration.
                goto start_time_input_loop
            )
        )
        set "start_sec_decimal=!padded_decimal!"
    )

    set "padded_start_seconds=0!start_sec!"
    set "padded_start_seconds=!padded_start_seconds:~-2!"
    set "start_time=!start_min!:!padded_start_seconds!.!start_sec_decimal!"

    set "temp_end_min=!end_min!"
    set "temp_end_sec=!end_sec!"
    set "temp_end_sec_decimal=!end_sec_decimal!"
    
    set "end_min=!total_minutes!"
    set "end_sec=!total_seconds!"
    set "end_sec_decimal=!total_seconds_decimal:~0,3!"
    
    call :display_timeline
    
    set "end_min=!temp_end_min!"
    set "end_sec=!temp_end_sec!"
    set "end_sec_decimal=!temp_end_sec_decimal!"

    echo Selected start time: !start_time!
    echo.
exit /b 0

:get_end_time
    echo Press Enter without input to use full video length (!total_minutes!:!padded_total_seconds!.!total_seconds_decimal:~0,3!)
    echo.

    :end_time_input_loop
    set "end_min=!total_minutes!"
    set "end_sec=!total_seconds!"
    set "end_sec_decimal=!total_seconds_decimal!"

    set /p "temp_input=End minutes (0-!total_minutes!): "
    if not "!temp_input!"=="" (
        if !temp_input! GTR !total_minutes! (
            echo Error: Minutes must be between 0 and !total_minutes!.
            goto end_time_input_loop
        )
        if !temp_input! LSS !start_min! (
            echo Error: End time must be after start time.
            goto end_time_input_loop
        )
        set "end_min=!temp_input!"
    )

    :get_end_seconds
    set /p "temp_input=End seconds (0-59): "
    if not "!temp_input!"=="" (
        if !temp_input! GEQ 60 (
            echo Error: Seconds must be between 0 and 59.
            goto get_end_seconds
        )
        set /a "total_end_seconds=!end_min! * 60 + !temp_input!"
        set /a "total_video_seconds=!total_minutes! * 60 + !total_seconds!"
        if !total_end_seconds! GTR !total_video_seconds! (
            echo Error: End time exceeds video duration.
            goto end_time_input_loop
        )
        if !end_min! EQU !start_min! (
            if !temp_input! LSS !start_sec! (
                echo Error: End time must be after start time.
                goto get_end_seconds
            )
        )
        set "end_sec=!temp_input!"
    )

    :get_end_decimal
    set /p "temp_input=End seconds decimal (0-999): "
    if "!temp_input!"=="" (
        if not "!end_min!!end_sec!"=="!total_minutes!!total_seconds!" (
            set "end_sec_decimal=000"
        )
    ) else (
        set "padded_decimal=00!temp_input!"
        set "padded_decimal=!padded_decimal:~-3!"
        
        if !end_min! EQU !total_minutes! if !end_sec! EQU !total_seconds! (
            if !temp_input! GTR !total_seconds_decimal! (
                echo Error: End time exceeds video duration.
                goto end_time_input_loop
            )
        )
        if !end_min! EQU !start_min! if !end_sec! EQU !start_sec! (
            if !temp_input! LEQ !start_sec_decimal! (
                echo Error: End time must be after start time.
                goto get_end_decimal
            )
        )
        set "end_sec_decimal=!padded_decimal!"
    )

    set "padded_end_seconds=0!end_sec!"
    set "padded_end_seconds=!padded_end_seconds:~-2!"
    set "end_sec_decimal=!end_sec_decimal:~0,3!"
    set "end_time=!end_min!:!padded_end_seconds!.!end_sec_decimal!"

    call :display_timeline

    echo Selected end time: !end_time!
    echo.
exit /b 0

:calculate_duration
    set /a "start_ms=(!start_min! * 60000) + (!start_sec! * 1000) + !start_sec_decimal!"
    set /a "end_ms=(!end_min! * 60000) + (!end_sec! * 1000) + !end_sec_decimal!"
    set /a "duration_ms=end_ms - start_ms"
    
    if !duration_ms! LEQ 0 (
        call :show_error "Invalid duration: end time must be after start time."
        exit /b 1
    )
    
    set /a "duration_seconds=duration_ms / 1000"
    set /a "duration_decimal=duration_ms %% 1000"
    set "padded_duration_decimal=00!duration_decimal!"
    set "padded_duration_decimal=!padded_duration_decimal:~-3!"
    set "duration=!duration_seconds!.!padded_duration_decimal!"
exit /b 0

:display_timeline
    set /a "total_min_ms=!total_minutes! * 60000"
    set /a "total_sec_ms=!total_seconds! * 1000"
    set "padded_total_decimal=00!total_seconds_decimal!"
    set "padded_total_decimal=!padded_total_decimal:~-3!"
    set /a "total_ms=!total_min_ms! + !total_sec_ms!"
    
    set /a "start_min_ms=!start_min! * 60000"
    set /a "start_sec_ms=!start_sec! * 1000"
    set /a "start_ms=!start_min_ms! + !start_sec_ms!"
    
    set /a "end_min_ms=!end_min! * 60000"
    set /a "end_sec_ms=!end_sec! * 1000"
    set /a "end_ms=!end_min_ms! + !end_sec_ms!"
    
    if !total_ms! LEQ 0 (
        set "start_pos=0"
        set "end_pos=50"
    ) else (
        set /a "start_pos=(!start_ms! * 50) / !total_ms!"
        set /a "end_pos=(!end_ms! * 50) / !total_ms!"
    )
    
    if !start_pos! LSS 0 set "start_pos=0"
    if !end_pos! GTR 50 set "end_pos=50"
    if !start_pos! GTR 50 set "start_pos=50"
    if !end_pos! LSS 0 set "end_pos=0"
    
    set "timeline="
    for /l %%i in (0,1,50) do (
        if %%i LSS !start_pos! (
            set "timeline=!timeline!-"
        ) else if %%i LEQ !end_pos! (
            set "timeline=!timeline!#"
        ) else (
            set "timeline=!timeline!-"
        )
    )
    
    echo [!timeline!]
    if defined start_time echo  !start_time!
    if defined end_time echo  !end_time!
    echo.
exit /b 0

:confirm_time_range
    :confirm_loop
    set /p "confirm=Is this range correct? (y/n): "
    if /i "!confirm!"=="n" exit /b 1
    if /i "!confirm!"=="y" exit /b 0
    echo Please enter 'y' or 'n'
    goto confirm_loop
exit /b 0

:get_conversion_parameters
    call :get_fps_input
    if errorlevel 1 exit /b 1

    call :get_height_input
    if errorlevel 1 exit /b 1

    call :get_size_input
    if errorlevel 1 exit /b 1

    call :select_dither
    if errorlevel 1 exit /b 1

    echo.
    echo ========== Conversion Summary ==========
    echo Input: !input_file!
    echo Output: !output_file!
    echo Time range: !start_time! - !end_time!
    echo Duration: !duration!
    echo Output FPS: !fps!
    echo Height: !height!
    echo Target size: !target_size_mb! MB
    echo ======================================
exit /b 0

:get_fps_input
    echo.
    echo Source FPS: !source_fps!
    :retry_fps
    set /p "fps=fps=!fps! or fps=" <nul
    set /p "fps="
    if "!fps!"=="" set "fps=!CONFIG_INITIAL_FPS!"
    
    set "invalid="
    for /f "delims=0123456789" %%i in ("!fps!") do set "invalid=%%i"
    if defined invalid (
        echo Error: FPS must be a number.
        set "fps=!CONFIG_INITIAL_FPS!"
        goto retry_fps
    )
    
    if !fps! LEQ 0 (
        echo Error: FPS must be greater than 0.
        set "fps=!CONFIG_INITIAL_FPS!"
        goto retry_fps
    )
    if !fps! GTR !source_fps! (
        echo Warning: Output FPS is higher than source FPS.
        set /p "continue=Continue? (y/n): "
        if /i "!continue!"=="n" goto retry_fps
    )
exit /b 0

:get_height_input
    echo.
    echo Current resolution: !original_width!x!original_height!
    :retry_height
    set /p "height=height=!original_height! or height=" <nul
    set /p "height="
    if "!height!"=="" set "height=!original_height!"
    
    set "invalid="
    for /f "delims=0123456789" %%i in ("!height!") do set "invalid=%%i"
    if defined invalid (
        echo Error: Height must be a number.
        set "height=!original_height!"
        goto retry_height
    )
    
    if !height! LSS !min_height! (
        echo Error: Height must be at least !min_height! pixels.
        set "height=!original_height!"
        goto retry_height
    )
    if !height! GTR !original_height! (
        echo Warning: Output height is larger than source height.
        set /p "continue=Continue? (y/n): "
        if /i "!continue!"=="n" goto retry_height
    )
exit /b 0

:get_size_input
    echo.
    :retry_size
    set /p "target_size_mb=size=!target_size_mb!mb or size=" <nul
    set /p "target_size_mb="
    if "!target_size_mb!"=="" set "target_size_mb=!CONFIG_INITIAL_TARGET_SIZE_MB!"
    
    set "invalid="
    for /f "delims=0123456789" %%i in ("!target_size_mb!") do set "invalid=%%i"
    if defined invalid (
        echo Error: Size must be a number.
        set "target_size_mb=!CONFIG_INITIAL_TARGET_SIZE_MB!"
        goto retry_size
    )
    
    if !target_size_mb! LEQ 0 (
        echo Error: Size must be greater than 0 MB.
        set "target_size_mb=!CONFIG_INITIAL_TARGET_SIZE_MB!"
        goto retry_size
    )
    set /a "target_size=!target_size_mb! * 1024 * 1024"
exit /b 0

:select_dither
    echo.
    set /p "ans=Enable dithering? (y/n): "
    if /I "!ans!"=="y" (
        set "dither_option==dither=bayer:bayer_scale=1"
    ) else (
        set "dither_option="
    )
exit /b 0



:process_gif
    for %%A in ("!input_file!") do (
        set "output_file=%%~dpnA.gif"
        set "palette_file=%%~dpnA_palette.png"
    )

    set /a "low_height=!min_height!"
    set /a "high_height=!height!"
    set "tries=0"
    set "current_height=!height!"
    set "last_height=0"

    echo ----------------------------------------------------
    echo [PALETTE COMMAND]
    echo ffmpeg -y -v warning -stats -ss !start_time! -t !duration! -i "!input_file!" -vf "fps=!fps!,scale=-1:!current_height!:flags=lanczos,palettegen=stats_mode=single" -frames:v 1 -update 1 "!palette_file!"
    echo.
    echo [GIF COMMAND]
    echo ffmpeg -y -v warning -stats -ss !start_time! -t !duration! -i "!input_file!" -i "!palette_file!" -filter_complex "[0:v] fps=!fps!,scale=-1:!current_height!:flags=lanczos [x];[x][1:v] paletteuse!dither_option!" -c:v gif "!output_file!"
    echo ----------------------------------------------------
    echo.

    :generate_loop
        set /a "tries+=1"
        
        echo.
        echo ========== Trial !tries! of !max_tries! ==========
        echo Attempting with height: !current_height!
        echo Time parameters: Start=!start_time!s Duration=!duration!s

        if !current_height! NEQ !last_height! (
            set "regenerate_palette=1"
        ) else (
            set "regenerate_palette=0"
        )

        if !regenerate_palette! EQU 1 (
            echo Generating new palette for height: !current_height!
            if exist "!palette_file!" del "!palette_file!"
            call :generate_palette "!input_file!" "!palette_file!" || (
                if exist "!palette_file!" del "!palette_file!"
                exit /b 1
            )
            set "last_height=!current_height!"
        ) else (
            echo Reusing existing palette
        )

        call :generate_gif "!input_file!" "!palette_file!" "!output_file!" || (
            if exist "!palette_file!" del "!palette_file!"
            exit /b 1
        )
        
        call :check_file_size "!output_file!" || exit /b 1

        if !tries! GEQ !max_tries! (
            if !filesize! GTR !target_size! (
                echo Maximum tries reached. Best attempt: !filesize! bytes
                if exist "!palette_file!" del "!palette_file!"
                exit /b 0
            )
            echo Maximum tries reached. Last attempt: !filesize! bytes
            if exist "!palette_file!" del "!palette_file!"
            exit /b 0
        )

        if !filesize! GTR !target_size! (
            if !tries!==1 (
                echo.
                echo File size exceeds target size.
                echo Starting binary search to find optimal height for target file size...
                echo.
            )
            if !current_height! LEQ !min_height! (
                echo Reached minimum height. Best attempt: !filesize! bytes
                if exist "!palette_file!" del "!palette_file!"
                exit /b 0
            )
            set /a "high_height=current_height - 1"
            set /a "current_height=(low_height + high_height) / 2"
            if !current_height! LSS !min_height! (
                set "current_height=!min_height!"
            )
        ) else (
            set /a "size_diff=target_size - filesize"
            if !size_diff! LSS 1048576 (
                echo Target size achieved within 1MB tolerance. File size: !filesize! bytes
                if exist "!palette_file!" del "!palette_file!"
                exit /b 0
            )
            if !tries!==1 (
                echo First try successful. File size: !filesize! bytes
                if exist "!palette_file!" del "!palette_file!"
                exit /b 0
            )
            set /a "low_height=current_height + 1"
            set /a "current_height=(low_height + high_height) / 2"
        )
        
        if !current_height! EQU !height! (
            echo Height optimization complete. File size: !filesize! bytes
            if exist "!palette_file!" del "!palette_file!"
            exit /b 0
        )
        goto generate_loop
exit /b 0

:generate_palette
    set "input=%~1"
    set "palette=%~2"

    ffmpeg -y -v warning -stats -ss !start_time! -t !duration! -i "!input!" ^
        -vf "fps=!fps!,scale=-1:!current_height!:flags=lanczos,palettegen=stats_mode=single" ^
        -frames:v 1 -update 1 "!palette!"

    if errorlevel 1 (
        call :show_error "Error occurred while generating palette."
        if exist "!palette!" del "!palette!"
        exit /b 1
    )
exit /b 0


:generate_gif
    set "input=%~1"
    set "palette=%~2"
    set "output=%~3"

    ffmpeg -y -v warning -stats -ss !start_time! -t !duration! -i "!input!" -i "!palette!" ^
        -filter_complex "[0:v] fps=!fps!,scale=-1:!current_height!:flags=lanczos [x];[x][1:v] paletteuse!dither_option!" ^
        -c:v gif "!output!"

    if errorlevel 1 (
        call :show_error "Error occurred while generating GIF."
        if exist "!palette!" del "!palette!"
        exit /b 1
    )
exit /b 0


:check_file_size
    set "output=%~1"
    for %%I in ("!output!") do set "filesize=%%~zI"
    echo Trial !tries!: Current file size: !filesize! bytes
exit /b 0

:display_results
    if exist "!output_file!" (
        echo.
        echo ========== Conversion Complete ==========
        echo Input: !input_file!
        echo Output: !output_file!
        echo Original resolution: !original_width!x!original_height!
        echo Final height: !current_height!
        echo Time range: !start_time! - !end_time!
        echo Duration: !duration!
        echo Source FPS: !source_fps!
        echo Output FPS: !fps!
        echo Output file size: !filesize! bytes (!target_size! bytes target)
        echo Total tries: !tries!
        echo ====================================
        exit /b 0
    ) else (
        call :show_error "No output file generated."
        exit /b 1
    )

:show_error
    echo Error: %~1
exit /b 1