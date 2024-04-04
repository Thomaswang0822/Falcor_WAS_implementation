# [Credits] This script was created by [Thomas Wang] with assistance from ChatGPT.
# and it should be run in the root directory

#!/bin/bash

# Set the original path based on the argument, defaulting to "results" if no argument is provided
if [[ "$1" == "refs" ]]; then
    original_path="tests/data/refs"
elif [[ "$1" == "results" ]]; then
    original_path="tests/data/results"
else
    original_path="tests/data/results"
fi

# Define the fixed intermediate path
intermediate_path="windows-ninja-msvc-Release/renderpasses"
destination_path="img_test_results"

# Loop through each branch folder
for branch_folder in "$original_path"/*; do
    branch_name=$(basename "$branch_folder")

    # Construct the destination branch path
    destination_branch_path="$destination_path/$branch_name"

    # Create destination branch folder if not exists
    mkdir -p "$destination_branch_path"

    echo "Processing branch: $branch_name"

    # Loop through each test folder
    for test_folder in "$branch_folder/$intermediate_path/test_"*"_d3d12"; do
        test_name=$(basename "$test_folder")

        echo "Processing test: $test_name"

        # Get the test type from the folder name
        if [[ "$test_name" == "test_WARDiffPathTracerTranslationBwd_d3d12" ]]; then
            new_filename="bwd.exr"
        elif [[ "$test_name" == "test_WARDiffPathTracerTranslationFwd_d3d12" ]]; then
            new_filename="fwd.exr"
        else
            continue
        fi

        # Check if source file exists
        if [[ ! -e "$test_folder/default.AccumulatePassDiff.output.1024.exr" ]]; then
            echo "Source file not found: $test_folder/default.AccumulatePassDiff.output.1024.exr"
            continue
        fi

        # Copy and rename the EXR file
        echo "Copying $test_folder/default.AccumulatePassDiff.output.1024.exr to $destination_branch_path/$new_filename"
        cp "$test_folder/default.AccumulatePassDiff.output.1024.exr" "$destination_branch_path/$new_filename"
    done
done
