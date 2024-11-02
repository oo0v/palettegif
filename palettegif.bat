@echo off
setlocal enabledelayedexpansion

:: ============================================
:: Configuration Variables
:: ============================================
call :init_config
if errorlevel 1 goto error_exit

:: ============================================
:: Main
:: ============================================
call :init_config
if errorlevel 1 goto error_exit

set "input_file=%~1"
if "!input_file!"=="" (
    call :show_error "No input file specified."
    goto error_exit
)

call :get_video_info "!input_file!"
if errorlevel 1 goto error_exit

call :display_video_info

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
    
    set "start_time_whole=0"
    set "start_time=0.0"
    set /a "end_time_whole=!total_minutes! * 60 + !end_seconds!"
    set "end_time=!end_time_whole!.!total_seconds_decimal!"
    
    call :calculate_duration
    if errorlevel 1 goto error_exit
    
    echo Using full video length:
    echo Start: 0:00.000
    echo End: !total_minutes!:!padded_total_seconds!.!total_seconds_decimal!
    echo Duration: !duration!
    echo.
) else (
    echo Please enter 'y' or 'n'
    echo.
    goto ask_time_range
)

    call :get_conversion_parameters
    if errorlevel 1 goto error_exit

    :: Generate output filename (remove any existing extension and add .gif)
    set "output_file=%~dpn1.gif"

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
    echo.
    
    :confirm_conversion
    set /p "confirm=Start conversion? (y/n): "
    if /i "!confirm!"=="n" (
        echo Conversion cancelled.
        goto end_script
    )
    if /i "!confirm!"=="y" (
        call :process_gif
        if errorlevel 1 goto error_exit

        call :display_results
        goto end_script
    )
    echo Please enter 'y' or 'n'
    goto confirm_conversion

goto main_loop

:: ============================================
:: Functions
:: ============================================

:init_config
    :: Initial configuration values
    set "CONFIG_INITIAL_FPS=20"
    set "CONFIG_INITIAL_TARGET_SIZE_MB=15"
    set "CONFIG_MIN_HEIGHT=40"
    set "CONFIG_MAX_TRIES=10"
    set "CONFIG_TIMELINE_WIDTH=50"

    :: Working variables
    set "fps=!CONFIG_INITIAL_FPS!"
    set "target_size_mb=!CONFIG_INITIAL_TARGET_SIZE_MB!"
    set "min_height=!CONFIG_MIN_HEIGHT!"
    set "max_tries=!CONFIG_MAX_TRIES!"
    
    :: Time variables initialization
    set "start_min=0"
    set "start_sec=0"
    set "start_sec_decimal=0"
    set "end_min=0"
    set "end_sec=0"
    set "end_sec_decimal=0"
exit /b 0

:get_video_info
    set "video_file=%~1"
    
    :: Get duration
    for /f "tokens=1,2 delims=." %%a in ('ffprobe -v error -show_entries format^=duration -of default^=noprint_wrappers^=1:nokey^=1 "!video_file!"') do (
        set "total_duration_int=%%a"
        set "total_duration=%%a.%%b"
        set /a "total_minutes=%%a/60"
        set /a "total_seconds=%%a%%60"
        set "total_seconds_decimal=%%b"
    )

    :: Get video properties
    for /f "tokens=*" %%a in ('ffprobe -v error -select_streams v:0 -show_entries "stream=width,height,r_frame_rate,nb_frames,pix_fmt" -of csv^=s^=x:p^=0 "!video_file!"') do (
        for /f "tokens=1-5 delims=x," %%b in ("%%a") do (
            set "original_width=%%b"
            set "original_height=%%c"
            set "colorspace=%%d"
            set "source_fps_raw=%%e"
            set "frame_count=%%f"
        )
    )

    :: Calculate source FPS
    call :calculate_source_fps
exit /b 0

:calculate_source_fps
    for /f "tokens=1,2 delims=/" %%a in ("!source_fps_raw!") do (
        set /a "source_fps_num=%%a"
        set /a "source_fps_den=%%b"
        set /a "source_fps=!source_fps_num! / !source_fps_den!"
    )

    if "!frame_count!"=="" (
        set /a "frame_count=!source_fps! * !total_duration_int!"
    )
exit /b 0

:display_video_info
    set "padded_total_seconds=0!total_seconds!"
    set "padded_total_seconds=!padded_total_seconds:~-2!"

    echo Input file: !input_file!
    echo Resolution: !original_width!x!original_height!
    echo Duration: !total_minutes!:!padded_total_seconds!.!total_seconds_decimal!
    echo Frame count: !frame_count! frames
    echo Source FPS: !source_fps! (!source_fps_raw!)
    echo =====================================
    echo.
exit /b 0

:get_time_range
    :: Get start time
    :time_input_loop
    call :get_start_time
    if errorlevel 1 goto time_input_loop

    :: Get end time and validate duration
    :end_time_loop
    call :get_end_time
    if errorlevel 1 goto end_time_loop

    :: Calculate and validate duration
    call :calculate_duration
    if errorlevel 1 (
        echo Press Enter to retry time input...
        echo.
        pause > nul
        goto time_input_loop
    )

    :: Display and confirm time range
    call :display_timeline
    call :confirm_time_range
    if errorlevel 1 goto time_input_loop
exit /b 0

:get_start_time
    echo Maximum time is !total_minutes!:!padded_total_seconds!.!total_seconds_decimal!
    echo Press Enter without input to start from beginning (0:00.000)
    echo.
    
    :start_time_input_loop
    :: Initialize with default values
    set "start_min=0"
    set "start_sec=0"
    set "start_sec_decimal=0"

    :: Get and display minutes
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
    
    :: Get and display seconds
    set /p "temp_input=Start seconds (0-59): "
    if "!temp_input!"=="" (
        echo 0
    ) else (
        if !temp_input! GEQ 60 (
            echo Error: Seconds must be between 0 and 59.
            goto start_time_input_loop
        )
        set "start_sec=!temp_input!"
    )
    
    :: Get and display decimal seconds
    set /p "temp_input=Start seconds decimal (0-999): "
    if "!temp_input!"=="" (
        echo 0
    ) else (
        if !temp_input! GEQ 1000 (
            echo Error: Decimal part must be between 0 and 999.
            goto start_time_input_loop
        )
        set "start_sec_decimal=!temp_input!"
    )

    :: Set start time values
    set /a "start_time_whole=!start_min! * 60 + !start_sec!"
    set "start_time=!start_time_whole!.!start_sec_decimal!"

    :: Display intermediate timeline after start time input
    call :display_intermediate_timeline
    
    :: Show selected start time
    echo Selected start time: !start_min!:!padded_start_seconds!.!start_sec_decimal!
    echo.
exit /b 0

:display_intermediate_timeline
    :: Format start time for display
    set "padded_start_seconds=0!start_sec!"
    set "padded_start_seconds=!padded_start_seconds:~-2!"

    :: Initialize timeline
    set "timeline="
    
    :: Generate timeline visualization
    set /a "total_positions=!CONFIG_TIMELINE_WIDTH!-1"
    for /l %%i in (0,1,!total_positions!) do (
        set /a "current_pos=%%i * total_duration_int / total_positions"
        if !current_pos! GEQ !start_time_whole! (
            set "timeline=!timeline!#"
        ) else (
            set "timeline=!timeline!-"
        )
    )

    :: Display timeline
    echo.
    echo Video Timeline  [!total_minutes!:!padded_total_seconds!.!total_seconds_decimal! total]
    echo [!timeline!]
    echo  !start_min!:!padded_start_seconds!.!start_sec_decimal! (Start Position)
    echo.
exit /b 0

:get_end_time
    echo Press Enter without input to use full video length (!total_minutes!:!padded_total_seconds!.!total_seconds_decimal!)
    echo.

    :end_time_input_loop
    :: Initialize with default values
    set "end_min=!total_minutes!"
    set "end_sec=!total_seconds!"
    set "end_sec_decimal=!total_seconds_decimal!"

    :: Get and display minutes
    set /p "temp_input=End minutes (0-!total_minutes!): "
    if "!temp_input!"=="" (
        echo !total_minutes!
    ) else (
        if !temp_input! GTR !total_minutes! (
            echo Error: Minutes must be between 0 and !total_minutes!.
            goto end_time_input_loop
        )
        set "end_min=!temp_input!"
    )
    
    :: Get and display seconds
    set /p "temp_input=End seconds (0-59): "
    if "!temp_input!"=="" (
        echo !total_seconds!
    ) else (
        if !temp_input! GEQ 60 (
            echo Error: Seconds must be between 0 and 59.
            goto end_time_input_loop
        )
        set "end_sec=!temp_input!"
    )
    
    :: Get and display decimal seconds
    set /p "temp_input=End seconds decimal (0-999): "
    if "!temp_input!"=="" (
        echo !total_seconds_decimal!
    ) else (
        if !temp_input! GEQ 1000 (
            echo Error: Decimal part must be between 0 and 999.
            goto end_time_input_loop
        )
        set "end_sec_decimal=!temp_input!"
    )

    :: Calculate total seconds and validate against maximum time
    set /a "end_time_whole=!end_min! * 60 + !end_sec!"
    set /a "total_time_whole=!total_minutes! * 60 + !total_seconds!"

    if !end_time_whole! GTR !total_time_whole! (
        echo Error: Specified time exceeds video length.
        goto end_time_input_loop
    )
    if !end_time_whole! EQU !total_time_whole! (
        if !end_sec_decimal! GTR !total_seconds_decimal! (
            echo Error: Specified time exceeds video length.
            goto end_time_input_loop
        )
    )

    :: Set end time values
    set "end_time=!end_time_whole!.!end_sec_decimal!"

    :: Format end time display (add padding)
    set "padded_end_seconds=0!end_sec!"
    set "padded_end_seconds=!padded_end_seconds:~-2!"

    :: Show selected end time
    echo Selected end time: !end_min!:!padded_end_seconds!.!end_sec_decimal!
    echo.
exit /b 0

:display_timeline
    :: Initialize timeline variables
    set "timeline="
    set "has_hash="
    
    :: Generate timeline visualization
    set /a "total_positions=!CONFIG_TIMELINE_WIDTH!-1"
    for /l %%i in (0,1,!total_positions!) do (
        set /a "current_pos=%%i * total_duration_int / total_positions"
        if !current_pos! GEQ !start_time_whole! (
            if defined duration (
                set /a "end_pos=start_time_whole + duration_whole"
                if !current_pos! LEQ !end_pos! (
                    set "timeline=!timeline!#"
                    set "has_hash=1"
                ) else (
                    set "timeline=!timeline!-"
                )
            ) else (
                set "timeline=!timeline!#"
                set "has_hash=1"
            )
        ) else (
            set "timeline=!timeline!-"
        )
    )

    :: Format time display
    call :format_time_display

    :: Calculate middle points for timeline markers
    if defined duration (
        set /a "mid_time_whole=(start_time_whole + end_time_whole) / 2"
        set /a "quarter_time_whole=(start_time_whole * 3 + end_time_whole) / 4"
        set /a "three_quarter_time_whole=(start_time_whole + end_time_whole * 3) / 4"
        
        set /a "mid_min=mid_time_whole / 60"
        set /a "mid_sec=mid_time_whole %% 60"
        set "padded_mid_sec=0!mid_sec!"
        set "padded_mid_sec=!padded_mid_sec:~-2!"

        set /a "quarter_min=quarter_time_whole / 60"
        set /a "quarter_sec=quarter_time_whole %% 60"
        set "padded_quarter_sec=0!quarter_sec!"
        set "padded_quarter_sec=!padded_quarter_sec:~-2!"

        set /a "three_quarter_min=three_quarter_time_whole / 60"
        set /a "three_quarter_sec=three_quarter_time_whole %% 60"
        set "padded_three_quarter_sec=0!three_quarter_sec!"
        set "padded_three_quarter_sec=!padded_three_quarter_sec:~-2!"
    )

    :: Display timeline and time information
    echo.
    echo Video Timeline  [!total_minutes!:!padded_total_seconds!.!total_seconds_decimal! total]
    echo [!timeline!]
    echo  !start_min!:!padded_start_seconds!.!start_sec_decimal!
    if defined duration (
        echo  !quarter_min!:!padded_quarter_sec!
        echo  !mid_min!:!padded_mid_sec!
        echo  !three_quarter_min!:!padded_three_quarter_sec!
        echo  !end_min!:!padded_end_seconds!.!end_sec_decimal!
    ) else (
        echo  (Full length)
    )
    echo.
    
    if not defined duration (
        echo Selected: !start_min!:!padded_start_seconds!.!start_sec_decimal! - Full length
    ) else (
        echo Selected: !start_min!:!padded_start_seconds!.!start_sec_decimal! - !end_min!:!padded_end_seconds!.!end_sec_decimal!
        echo Duration: !duration_minutes!:!padded_duration_seconds!.!duration_decimal!
    )
    echo.
exit /b 0

:format_time_display
    :: Format start time
    set "padded_start_seconds=0!start_sec!"
    set "padded_start_seconds=!padded_start_seconds:~-2!"

    :: Format end time if defined
    if defined duration (
        set "padded_end_seconds=0!end_sec!"
        set "padded_end_seconds=!padded_end_seconds:~-2!"
        
        :: Calculate duration display
        set /a "duration_minutes=duration_whole / 60"
        set /a "duration_seconds=duration_whole %% 60"
        set "padded_duration_seconds=0!duration_seconds!"
        set "padded_duration_seconds=!padded_duration_seconds:~-2!"
    )
exit /b 0

:calculate_duration
    :: Calculate whole seconds duration
    set /a "duration_whole=end_time_whole - start_time_whole"

    :: Calculate decimal part of duration
    if !end_sec_decimal! GEQ !start_sec_decimal! (
        set "duration_decimal=!end_sec_decimal!"
    ) else (
        set /a "duration_whole-=1"
        set /a "duration_decimal=1000 + !end_sec_decimal! - !start_sec_decimal!"
    )

    :: Ensure duration is positive
    if !duration_whole! LSS 0 (
        call :show_error "Invalid duration: end time must be after start time."
        exit /b 1
    )
    if !duration_whole!==0 (
        if !duration_decimal! LEQ 0 (
            call :show_error "Invalid duration: end time must be after start time."
            exit /b 1
        )
    )

    set "duration=!duration_whole!.!duration_decimal!"
exit /b 0

:confirm_time_range
    :confirm_loop
    set /p "confirm=Is this range correct? (y/n): "
    if /i "!confirm!"=="n" (
        echo Press Enter to retry time input...
        echo.
        pause > nul
        exit /b 1
    )
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
exit /b 0

:get_fps_input
    echo.
    echo Source FPS: !source_fps!
    set /p "fps=fps=!fps! or fps=" <nul
    set /p "fps="
    if "!fps!"=="" set "fps=!CONFIG_INITIAL_FPS!"
    
    :: Validate FPS input
    set "non_numeric="
    for /f "delims=0123456789" %%a in ("!fps!") do set "non_numeric=%%a"
    if defined non_numeric (
        set "fps=!CONFIG_INITIAL_FPS!"
        call :show_error "Please enter a valid FPS."
        exit /b 1
    )
    if !fps! LEQ 0 (
        call :show_error "FPS must be greater than 0."
        exit /b 1
    )
    if !fps! GTR !source_fps! (
        echo Warning: Output FPS is higher than source FPS.
        set /p "continue=Continue? (y/n): "
        if /i "!continue!"=="n" exit /b 1
    )
exit /b 0

:get_height_input
    echo.
    echo Current resolution: !original_width!x!original_height!
    set /p "height=height=!original_height! or height=" <nul
    set /p "height="
    if "!height!"=="" set "height=!original_height!"
    
    :: Validate height input
    set "non_numeric="
    for /f "delims=0123456789" %%a in ("!height!") do set "non_numeric=%%a"
    if defined non_numeric (
        set "height=!original_height!"
        call :show_error "Please enter a valid height."
        exit /b 1
    )
    if !height! LSS !min_height! (
        call :show_error "Height must be at least !min_height! pixels."
        exit /b 1
    )
    if !height! GTR !original_height! (
        echo Warning: Output height is larger than source height.
        set /p "continue=Continue? (y/n): "
        if /i "!continue!"=="n" exit /b 1
    )
exit /b 0

:get_size_input
    echo.
    set /p "target_size_mb=size=!target_size_mb!mb or size=" <nul
    set /p "target_size_mb="
    if "!target_size_mb!"=="" set "target_size_mb=!CONFIG_INITIAL_TARGET_SIZE_MB!"
    
    :: Validate size input
    set "non_numeric="
    for /f "delims=0123456789" %%a in ("!target_size_mb!") do set "non_numeric=%%a"
    if defined non_numeric (
        set "target_size_mb=!CONFIG_INITIAL_TARGET_SIZE_MB!"
        call :show_error "Please enter a valid size in MB."
        exit /b 1
    )
    if !target_size_mb! LEQ 0 (
        call :show_error "Size must be greater than 0 MB."
        exit /b 1
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

    set /a "low_height=!min_height!"
    set /a "high_height=!height!"
    set "tries=0"

    :generate_loop
        set /a "tries+=1"
        if !tries!==1 (
            set "current_height=!height!"
        ) else (
            set /a "current_height=(low_height + high_height) / 2"
        )

        echo.
        echo ========== Trial !tries! of !max_tries! ==========
        echo Attempting with height: !current_height!
        echo Time parameters: Start=!start_time!s Duration=!duration!s

        call :generate_palette "!input_file!" "!palette_file!" || exit /b 1
        call :generate_gif "!input_file!" "!palette_file!" "!output_file!" || exit /b 1
        call :check_file_size "!output_file!" || exit /b 1

        if !tries! GEQ !max_tries! (
            if !filesize! GTR !target_size! (
                echo Maximum tries reached. Deleting output file.
                if exist "!output_file!" del "!output_file!"
                exit /b 1
            )
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
                exit /b 0
            )
            set /a "high_height=current_height - 1"
            goto generate_loop
        ) else (
            set /a "size_diff=target_size - filesize"
            if !size_diff! LSS 1048576 (
                echo Target size achieved within 1MB tolerance. File size: !filesize! bytes
                exit /b 0
            )
            if !tries!==1 (
                echo First try successful. File size: !filesize! bytes
                exit /b 0
            )
            set /a "low_height=current_height + 1"
            goto generate_loop
        )
exit /b 0

:generate_palette
    set "input=%~1"
    set "palette=%~2"

    ffmpeg -y -v warning -stats -ss !start_time! -t !duration! -i "!input!" ^
        -vf "fps=!fps!,scale=-1:!current_height!:flags=spline,palettegen" ^
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

    ffmpeg -y -v warning -stats -ss !start_time! -t !duration! -i "!input!" -i "!palette!" ^
        -filter_complex "[0:v] fps=!fps!,scale=-1:!current_height!:flags=spline [x]; [x][1:v] paletteuse" ^
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

:error_exit
    pause
    exit /b 1

:end_script
    if exist "!palette_file!" del "!palette_file!"
    pause
    exit /b 0