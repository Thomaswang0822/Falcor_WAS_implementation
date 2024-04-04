: [Credits] This script was created by [Thomas Wang] with assistance from ChatGPT.
: and it should be run in the root directory

@echo off
setlocal enabledelayedexpansion

REM Define the base paths
set "original_path=tests\data\refs"
set "destination_path=img_test_results"

REM Define the fixed intermediate path
set "intermediate_path=windows-ninja-msvc-Release\renderpasses"

REM Loop through each branch folder
for /d %%A in ("%original_path%\*") do (
    set "branch_folder=%%A"
    set "branch_name=%%~nxA"
    set "destination_branch_path=%destination_path%\!branch_name!"

    REM Create destination branch folder if not exists
    if not exist "!destination_branch_path!" (
        mkdir "!destination_branch_path!"
    )

    echo Processing branch: !branch_name!

    REM Loop through each test folder
    for /d %%B in ("!branch_folder!\%intermediate_path%\test_*_d3d12") do (
        set "test_folder=%%B"

        REM Extract just the name of the test directory
        for %%C in ("!test_folder!") do set "test_name=%%~nxC"

        echo Processing test: !test_name!

        REM Get the test type from the folder name
        if "!test_name!"=="test_WARDiffPathTracerTranslationBwd_d3d12" (
            set "new_filename=bwd.exr"
        ) else if "!test_name!"=="test_WARDiffPathTracerTranslationFwd_d3d12" (
            set "new_filename=fwd.exr"
        ) else (
            goto :next_iteration
        )

        REM Check if source file exists
        if not exist "!test_folder!\default.AccumulatePassDiff.output.1024.exr" (
            echo Source file not found: "!test_folder!\default.AccumulatePassDiff.output.1024.exr"
            goto :next_iteration
        )

        REM Copy and rename the EXR file
        echo Copying "!test_folder!\default.AccumulatePassDiff.output.1024.exr" to "!destination_branch_path!\!new_filename!"
        copy "!test_folder!\default.AccumulatePassDiff.output.1024.exr" "!destination_branch_path!\!new_filename!" >nul

        :next_iteration
        REM Skip the current iteration and proceed to the next one
    )
)

goto :eof

