# reusable functions

# Function to replace variable placeholders in files with format ##VAR_NAME## with actual values
# Usage: replace_var_in_files <file_path>
replace_var_in_files () {
  FILE_PATH=$1
  for PARAM_KEY in $(grep -o '##[^#]*##' "$FILE_PATH" | sed 's/##//g'); do
    PARAM_VALUE=${!PARAM_KEY}

    if [ -z $PARAM_VALUE ]; then
        echo "Error: Variable '$PARAM_KEY ' is not set." >&2
        exit 1
    fi

    sed -i "s|##$PARAM_KEY##|$PARAM_VALUE|g" "$FILE_PATH"
  done
}