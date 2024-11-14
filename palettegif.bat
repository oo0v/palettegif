@echo off
setlocal enabledelayedexpansion

set "CONFIG_INITIAL_FPS=20"
set "CONFIG_INITIAL_TARGET_SIZE_MB=15"
set "CONFIG_MIN_HEIGHT=40"
set "CONFIG_MAX_TRIES=10"
set "CONFIG_TIMELINE_WIDTH=50"
set "CONFIG_DEFAULT_ASPECT_RATIO=0"

set "fps=!CONFIG_INITIAL_FPS!"
set "target_size_mb=!CONFIG_INITIAL_TARGET_SIZE_MB!"
set "min_height=!CONFIG_MIN_HEIGHT!"
set "max_tries=!CONFIG_MAX_TRIES!"
set "aspect_ratio=!CONFIG_DEFAULT_ASPECT_RATIO!"
    
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
echo Duration: !total_minutes!:!padded_total_seconds!.!total_seconds_decimal!
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
    set "start_sec_decimal=0"
    set "end_min=!total_minutes!"
    set "end_sec=!total_seconds!"
    set "end_sec_decimal=!total_seconds_decimal!"
    
    set "start_time=0:00.000"
    set "end_time=!total_minutes!:!padded_total_seconds!.!total_seconds_decimal!"
    
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
    
    for /f "tokens=1,2 delims=." %%a in ('ffprobe -v error -show_entries format^=duration -of default^=noprint_wrappers^=1:nokey^=1 "!video_file!"') do (
        set "total_duration_int=%%a"
        set "total_duration=%%a.%%b"
        set /a "total_minutes=%%a/60"
        set /a "total_seconds=%%a%%60"
        set "total_seconds_decimal=%%b"
    )
    
    for /f "tokens=*" %%a in ('ffprobe -v error -select_streams v:0 -show_entries "stream=width,height,r_frame_rate,nb_frames,pix_fmt" -of csv^=s^=x:p^=0 "!video_file!"') do (
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

    call :display_timeline
    call :confirm_time_range
    if errorlevel 1 goto time_input_loop
exit /b 0

:get_start_time
    echo Maximum time is !total_minutes!:!padded_total_seconds!.!total_seconds_decimal!
    echo Press Enter without input to start from beginning (0:00.000)
    echo.
    
    :start_time_input_loop
    set "start_min=0"
    set "start_sec=0"
    set "start_sec_decimal=0"

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
        echo 0
    ) else (
        if !temp_input! GEQ 1000 (
            echo Error: Decimal part must be between 0 and 999.
            goto start_time_input_loop
        )
        if !start_min! EQU !total_minutes! if !start_sec! EQU !total_seconds! (
            if !temp_input! GTR %total_seconds_decimal:~0,3% (
                echo Error: Start time exceeds video duration.
                goto start_time_input_loop
            )
        )
        set "start_sec_decimal=!temp_input!"
    )

    set "padded_start_seconds=0!start_sec!"
    set "padded_start_seconds=!padded_start_seconds:~-2!"
    set "start_time=!start_min!:!padded_start_seconds!.!start_sec_decimal!"

    set /a "total_ms=(!total_minutes! * 60000) + (!total_seconds! * 1000) + %total_seconds_decimal:~0,3%"
    set /a "start_ms=(!start_min! * 60000) + (!start_sec! * 1000) + !start_sec_decimal!"
    
    set /a "start_pos=(start_ms * 50) / total_ms"
    
    echo.
    echo Video Timeline  [!total_minutes!:!padded_total_seconds!.!total_seconds_decimal! total]
    
    set "before="
    for /l %%i in (0,1,!start_pos!) do set "before=!before!-"
    set "after="
    for /l %%i in (!start_pos!,1,49) do set "after=!after!#"
    set "timeline=!before!!after!"
    
    echo [!timeline!]
    echo  !start_time!
    echo.
    
    echo Selected start time: !start_time!
    echo.
exit /b 0

:get_end_time
    echo Press Enter without input to use full video length (!total_minutes!:!padded_total_seconds!.!total_seconds_decimal!)
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
    if not "!temp_input!"=="" (
        if !temp_input! GEQ 1000 (
            echo Error: Decimal part must be between 0 and 999.
            goto get_end_decimal
        )
        if !end_min! EQU !total_minutes! if !end_sec! EQU !total_seconds! (
            if !temp_input! GTR !total_seconds_decimal! (
                echo Error: End time exceeds video duration.
                goto get_end_decimal
            )
        )
        if !end_min! EQU !start_min! if !end_sec! EQU !start_sec! (
            if !temp_input! LEQ !start_sec_decimal! (
                echo Error: End time must be after start time.
                goto get_end_decimal
            )
        )
        set "end_sec_decimal=!temp_input!"
    )

    set "padded_end_seconds=0!end_sec!"
    set "padded_end_seconds=!padded_end_seconds:~-2!"
    set "end_time=!end_min!:!padded_end_seconds!.!end_sec_decimal!"

    echo Selected end time: !end_time!
    echo.
exit /b 0

:calculate_duration
    set /a "start_ms=(!start_min! * 60 + !start_sec!) * 1000 + !start_sec_decimal!"
    set /a "end_ms=(!end_min! * 60 + !end_sec!) * 1000 + !end_sec_decimal!"
    set /a "duration_ms=end_ms - start_ms"
    set /a "duration_whole=duration_ms / 1000"
    set /a "duration_decimal=duration_ms %% 1000"
    
    if !duration_ms! LEQ 0 (
        call :show_error "Invalid duration: end time must be after start time."
        exit /b 1
    )
    set "duration=!duration_whole!.!duration_decimal!"
exit /b 0

:display_timeline
    set /a "total_ms=(!total_minutes! * 60000) + (!total_seconds! * 1000) + %total_seconds_decimal:~0,3%"
    set /a "start_ms=(!start_min! * 60000) + (!start_sec! * 1000) + !start_sec_decimal!"
    set /a "end_ms=(!end_min! * 60000) + (!end_sec! * 1000) + !end_sec_decimal!"
    
    echo.
    echo Video Timeline  [!total_minutes!:!padded_total_seconds!.!total_seconds_decimal! total]
    
    set /a "start_pos=(start_ms * 50) / total_ms"
    set /a "end_pos=(end_ms * 50) / total_ms"
    
    set "filled="
    for /l %%i in (0,1,!start_pos!) do set "filled=!filled!-"
    for /l %%i in (!start_pos!,1,!end_pos!) do set "filled=!filled!#"
    set "remaining="
    for /l %%i in (!end_pos!,1,50) do set "remaining=!remaining!-"
    set "timeline=!filled!!remaining!"
    
    echo [!timeline!]
    echo  !start_min!:!padded_start_seconds!.!start_sec_decimal!
    echo  !end_min!:!padded_end_seconds!.!end_sec_decimal!
    echo.
    echo Selected: !start_min!:!padded_start_seconds!.!start_sec_decimal! - !end_min!:!padded_end_seconds!.!end_sec_decimal!
    if defined duration (
        echo Duration: !duration!
    )
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

    call :get_aspect_ratio_input
    if errorlevel 1 exit /b 1

    call :get_size_input
    if errorlevel 1 exit /b 1

    echo.
    echo ========== Conversion Summary ==========
    echo Input: !input_file!
    echo Output: !output_file!
    echo Time range: !start_time! - !end_time!
    echo Duration: !duration!
    echo Output FPS: !fps!
    echo Height: !height!
    if !aspect_ratio! GTR 0 (
        set /a "target_width=!height! * !aspect_ratio_num! / !aspect_ratio_den!"
        echo Aspect Ratio: !aspect_ratio_num!:!aspect_ratio_den! ^(!target_width!x!height!^)
    ) else (
        echo Aspect Ratio: Original
    )
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

:get_aspect_ratio_input
    echo.
    echo Current aspect ratio: !original_width!:!original_height!
    echo Available aspect ratios:
    echo 1. Original ^(no change^)
    echo 2. 1:1 ^(square^)
    echo 3. 16:9 ^(widescreen^)
    echo 4. 4:3 ^(standard^)
    echo 5. 9:16 ^(vertical^)
    echo 6. Custom ^(e.g., 2:1^)
    
    :aspect_ratio_input_loop
    set /p "aspect_choice=Choose aspect ratio (1-6): "
    
    if "!aspect_choice!"=="1" (
        set "aspect_ratio=0"
        set "aspect_ratio_num=0"
        set "aspect_ratio_den=0"
    ) else if "!aspect_choice!"=="2" (
        set "aspect_ratio=1"
        set "aspect_ratio_num=1"
        set "aspect_ratio_den=1"
    ) else if "!aspect_choice!"=="3" (
        set "aspect_ratio=1.7778"
        set "aspect_ratio_num=16"
        set "aspect_ratio_den=9"
    ) else if "!aspect_choice!"=="4" (
        set "aspect_ratio=1.3333"
        set "aspect_ratio_num=4"
        set "aspect_ratio_den=3"
    ) else if "!aspect_choice!"=="5" (
        set "aspect_ratio=0.5625"
        set "aspect_ratio_num=9"
        set "aspect_ratio_den=16"
    ) else if "!aspect_choice!"=="6" (
        call :get_custom_aspect_ratio
        if errorlevel 1 goto aspect_ratio_input_loop
    ) else (
        echo Invalid choice. Please enter a number between 1 and 6.
        goto aspect_ratio_input_loop
    )
    
    if !aspect_ratio! GTR 0 (
        set /a "target_width=!height! * !aspect_ratio_num! / !aspect_ratio_den!"
        echo Selected aspect ratio: !aspect_ratio_num!:!aspect_ratio_den! ^(!target_width!x!height!^)
    ) else (
        echo Using original aspect ratio
    )
exit /b 0

:get_custom_aspect_ratio
    echo Enter custom aspect ratio (width:height, e.g. 2:1):
    set /p "custom_ratio="
    
    for /f "tokens=1,2 delims=:" %%a in ("!custom_ratio!") do (
        set "aspect_ratio_num=%%a"
        set "aspect_ratio_den=%%b"
    )
    
    set "non_numeric="
    for /f "delims=0123456789" %%a in ("!aspect_ratio_num!!aspect_ratio_den!") do set "non_numeric=%%a"
    if defined non_numeric (
        call :show_error "Please enter valid numbers for aspect ratio."
        exit /b 1
    )
    
    if !aspect_ratio_num! LEQ 0 (
        call :show_error "Width must be greater than 0."
        exit /b 1
    )
    if !aspect_ratio_den! LEQ 0 (
        call :show_error "Height must be greater than 0."
        exit /b 1
    )
    
    set /a "aspect_ratio=(!aspect_ratio_num! * 10000) / !aspect_ratio_den!"
    set /a "aspect_ratio_decimal=!aspect_ratio! %% 10000"
    set /a "aspect_ratio=!aspect_ratio! / 10000"
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

:process_gif
    set "output_file=!input_file!.gif"
    set "palette_file=!input_file!_palette.png"
    
    set "output_file=!output_file:.mov.gif=.gif!"
    set "output_file=!output_file:.mp4.gif=.gif!"
    set "output_file=!output_file:.avi.gif=.gif!"
    set "output_file=!output_file:.wmv.gif=.gif!"
    set "output_file=!output_file:.flv.gif=.gif!"
    set "output_file=!output_file:.mkv.gif=.gif!"
    set "output_file=!output_file:.mpg.gif=.gif!"
    set "output_file=!output_file:.3gp.gif=.gif!"
    set "output_file=!output_file:.ogv.gif=.gif!"
    set "output_file=!output_file:.webm.gif=.gif!"
    set "output_file=!output_file:.mpeg.gif=.gif!"

    set /a "low_height=!min_height!"
    set /a "high_height=!height!"
    set "tries=0"
    set "current_height=!height!"
    set "last_height=0"
    set "last_aspect=none"

    :generate_loop
        set /a "tries+=1"
        
        echo.
        echo ========== Trial !tries! of !max_tries! ==========
        echo Attempting with height: !current_height!
        echo Time parameters: Start=!start_time!s Duration=!duration!s

        if !current_height! NEQ !last_height! (
            set "regenerate_palette=1"
        ) else if !aspect_ratio! NEQ !last_aspect! (
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
            set "last_aspect=!aspect_ratio!"
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

    if !aspect_ratio! GTR 0 (
        set /a "crop_width=!current_height! * !aspect_ratio_num! / !aspect_ratio_den!"
        set "crop_filter=,crop=!crop_width!:!current_height!"
    ) else (
        set "crop_filter="
    )

    ffmpeg -y -v warning -stats -ss !start_time! -t !duration! -i "!input!" ^
        -vf "fps=!fps!,scale=-1:!current_height!:flags=spline!crop_filter!,palettegen" ^
        -update 1 -frames:v 1 "!palette!"
    
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

    if !aspect_ratio! GTR 0 (
        set /a "crop_width=!current_height! * !aspect_ratio_num! / !aspect_ratio_den!"
        set "crop_filter=,crop=!crop_width!:!current_height!"
    ) else (
        set "crop_filter="
    )

    ffmpeg -y -v warning -stats -ss !start_time! -t !duration! -i "!input!" -i "!palette!" ^
        -filter_complex "[0:v] fps=!fps!,scale=-1:!current_height!:flags=spline!crop_filter! [x]; [x][1:v] paletteuse" ^
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
        if !aspect_ratio! GTR 0 (
            set /a "final_width=!current_height! * !aspect_ratio_num! / !aspect_ratio_den!"
            echo Final resolution: !final_width!x!current_height!
            echo Aspect ratio: !aspect_ratio_num!:!aspect_ratio_den!
        )
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