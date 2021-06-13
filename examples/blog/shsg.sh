#!/bin/sh

#### Config ####{{{
. "./globals.sh"
# Required
readonly SRC_DIR="src"
readonly OUT_DIR="public"
readonly TEMPLATE_DIR="templates"
readonly QUIET=false
readonly CLEAR_BEFORE_BUILD=false

# Optional
readonly PARSER_CMD="pandoc --wrap=preserve -f gfm -t html"
readonly FORMAT_CMD=""
readonly BASE_TEMPLATE="templates/base.html"
readonly IGNORE_FILE=""

# Colors
readonly LOG_DEFAULT_COLOR="\033[0m"
readonly LOG_ERROR_COLOR="\033[1;31m"
readonly LOG_INFO_COLOR="\033[34m"
readonly LOG_SUCCESS_COLOR="\033[1;32m"
readonly LOG_ALT_COLOR="\033[1;35m"
readonly ARROW_DOWN="\t${LOG_INFO_COLOR}↓${LOG_DEFAULT_COLOR}\n\t"

#}}}[]

#### Utility functions (internal) ####{{{

__clog() {
	[ "$QUIET" = true ] && return 0
	[ "$CLI_QUIET" = true ] && return 0

	local __COLOR=""
	case "$1" in
	error)
		local __COLOR="$LOG_ERROR_COLOR"
		;;
	info)
		local __COLOR="$LOG_INFO_COLOR"
		;;
	success)
		local __COLOR="$LOG_SUCCESS_COLOR"
		;;
	alt)
		local __COLOR="$LOG_ALT_COLOR"
		;;
	esac

	[ -z "$__COLOR" ] && echo "BUG: Invalid color passed to log" && exit 1

	[ "$CLI_QUIET" != true ] &&
		echo -e ${__COLOR}${2}${LOG_DEFAULT_COLOR}$([ ! -z "$3" ] && echo "$3") >/dev/stderr
}

__clog_verbose() {
	[ "$CLI_VERBOSE" = true ] && __clog "$@"
}

__bail() {
	__clog error "Error: $1" && exit 1
}

__check_prg_exists() {
	local __PRG="${1%% *}"
	local __LABEL="$2"
	local __REQUIRED="$3"

	__check() {
		! command -v "$1" >/dev/null 2>&1 && __bail "$2 $1 does not exist"
	}

	if [ "$__REQUIRED" = true ]; then
		[ -z "$__PRG" ] && __bail "$__LABEL program is undefined" || __check "$__PRG" "$__LABEL"
	else
		[ ! -z "$__PRG" ] && __check "$__PRG" "$__LABEL"
	fi

}

__use_parser_prg() {
	[ ! -z "$PARSER_CMD" ] && eval "$PARSER_CMD" <<<"$1"
}

__infer_template_file() {
	local __SRC_FiLE_PATH="$1"
	local __EXTENSION="$2"

	local __RELATIVE_DIRNAME=$(dirname ${__SRC_FiLE_PATH/"$SRC_DIR"\//})
	local __BASENAME=$(basename ${__SRC_FiLE_PATH%.*})

	# Check for an exact match (e.g.: src/blog/post-1.md --> template/blog/__post-1.html)
	local __EXACT_MATCH="$TEMPLATE_DIR/$__RELATIVE_DIRNAME/__$__BASENAME.$__EXTENSION"
	[ -f "$__EXACT_MATCH" ] &&
		echo "$__EXACT_MATCH" &&
		return 0

	# Check for a match/deep match
	# Examples
	# src/blog/post-1.md --> templates/blog.html || templates/blog/index.html
	# src/blog/special/post-1/.md --> src/blog/special.html
	local __DEEPEST_MATCH=""

	IFS="/"
	for __DIR in $__RELATIVE_DIRNAME; do
		[ -f "$TEMPLATE_DIR/$__DIR.$__EXTENSION" ] &&
			local __DEEPEST_MATCH="$TEMPLATE_DIR/$__DIR.$__EXTENSION"

		[ -f "$TEMPLATE_DIR/$__DIR/index.$__EXTENSION" ] &&
			local __DEEPEST_MATCH="$TEMPLATE_DIR/$__DIR/index.$__EXTENSION"
	done
	IFS="$DEFAULT_IFS"

	[ ! -z "$__DEEPEST_MATCH" ] &&
		[ -f "$__DEEPEST_MATCH" ] &&
		echo "$__DEEPEST_MATCH" &&
		return 0
}

__infer_implicit_template_css_path() {
	local __FILE_PATH="$1"

	local __EXTENSION=$(get_extension "$__FILE_PATH")

	local __IMPLICIT_CSS="${__FILE_PATH%$__EXTENSION}css"

	[ -f "$__IMPLICIT_CSS" ] && echo "$__IMPLICIT_CSS"
}

__copy_implicit_template_css() {
	local __TEMPLATE="$1"
	local __SRC_FILE="$2"

	local __IMPLICIT_CSS_SRC=$(__infer_implicit_template_css_path "$__TEMPLATE")

	[ -z "$__IMPLICIT_CSS_SRC" ] && return 0

	local __SRC_FILE_DEST=$(infer_out_path "$__SRC_FILE")

	local __IMPLICIT_CSS_OUT=$(dirname "$__SRC_FILE_DEST")/$(basename "$__IMPLICIT_CSS_SRC")

	if ! cmp -s "$__IMPLICIT_CSS_SRC" "$__IMPLICIT_CSS_OUT"; then
		cp "$__IMPLICIT_CSS_SRC" "$__IMPLICIT_CSS_OUT" &&
			__clog_verbose success "\t↪ " "$__IMPLICIT_CSS_SRC $LOG_SUCCESS_COLOR(Copied)$LOG_DEFAULT_COLOR"
	else
		__clog_verbose info "\t↪ " "$__IMPLICIT_CSS_SRC $LOG_INFO_COLOR(No changes)$LOG_DEFAULT_COLOR"
	fi
}

__resolve_template() {
	local __TEMPLATE_FILE="$1"
	local __SRC_BODY="$2"
	local __SRC_FILE="$3"

	__recursive_resolve() {
		local __RECURSIVE_TEMPLATE="$1"
		local __RECURSIVE_BODY="$2"

		local __TEMPLATE_BODY=$(parse_body "$__RECURSIVE_TEMPLATE")
		local __TEMPLATE_FRONTMATTER=$(parse_frontmatter "$__RECURSIVE_TEMPLATE")

		set -a

		[ ! -z "$__TEMPLATE_FRONTMATTER" ] && eval "$__TEMPLATE_FRONTMATTER"

		BODY="$__RECURSIVE_BODY"

		set +a

		local __RECURSIVE_BODY=$(envsubst <<<"$__RECURSIVE_TEMPLATE")

		if [ ! -z "$INHERITS" ]; then
			__clog_verbose info '' "$ARROW_DOWN$INHERITS"
			__copy_implicit_template_css "$INHERITS" "$__SRC_FILE"

			__recursive_resolve "$INHERITS" "$__RECURSIVE_BODY"
		else
			if [ ! -z "$BASE_TEMPLATE" ]; then

				local __RECURSIVE_BODY=$(envsubst <"$BASE_TEMPLATE")

				__clog_verbose info '' "$ARROW_DOWN$BASE_TEMPLATE"
				__copy_implicit_template_css "$BASE_TEMPLATE" "$__SRC_FILE"
			fi
		fi

		unset $(__get_var_names "$__TEMPLATE_FRONTMATTER")
		unset BODY

		echo -e  "$__RECURSIVE_BODY"
	}

	local __RECURSIVE_OUT=$(__recursive_resolve "$__TEMPLATE_FILE" "$__SRC_BODY")

	echo "$__RECURSIVE_OUT"
}

__get_var_names() {
	echo "$1" | grep -i '^[a-z].*=' | grep -v "^export *" | sed 's/=.*//i'
}

#}}}

#### Utility functions (external) ####{{{

parse_frontmatter() {

	local __INPUT="$1"
	local __INPUT_EXTENSION="$(get_extension $__INPUT)"

	[ "$__INPUT_EXTENSION" = "md" ] && sed -n '1 { /---/ { :a N; /\n---/! ba; p} }' "$__INPUT" | head -n -1 | tail -n +2

	[ "$__INPUT_EXTENSION" = "html" ] && sed -n '/<\!\-\-FM/,/\-\->/{/<\!\-\-FM/b;/\-\->/b;p}' "$__INPUT"

	[ "$__INPUT_EXTENSION" = "sh" ] && cat "$__INPUT"

}

parse_body() {

	local __INPUT="$1"
	local __INPUT_EXTENSION="$(get_extension $__INPUT)"

	[ "$__INPUT_EXTENSION" = "md" ] && sed '1 { /^---/ { :a N; /\n---/! ba; d} }' "$__INPUT"

	[ "$__INPUT_EXTENSION" = "html" ] && sed '1 { /^<\!\-\-FM/ { :a N; /\-\->/! ba; d} }' "$__INPUT"
}

get_extension() {
	echo "${1##*.}"
}

infer_out_path() {
	local __IN_PATH="$1"

	local __IN_EXTENSION="$(get_extension $__IN_PATH)"

	local __OUT_EXTENSION=""

	[ "$__IN_EXTENSION" = "md" ] && local __OUT_EXTENSION="html"
	[ "$__IN_EXTENSION" = "sh" ] && local __OUT_EXTENSION="html"

	[ -z "$__OUT_EXTENSION" ] && local __OUT_EXTENSION="$__IN_EXTENSION"

	# Note here OUT_DIR SRC_DIR is reffering to the global declared in config.
	local __OUT_PATH_DIR="$(dirname ${__IN_PATH/$SRC_DIR/$OUT_DIR})"
	local __OUT_PATH_FILE="$(basename $__IN_PATH $__IN_EXTENSION)$__OUT_EXTENSION"

	echo "$__OUT_PATH_DIR/$__OUT_PATH_FILE"
}

#}}}

#### Build ####{{{

__build_preflight() {
	__check_prg_exists "$PARSER_CMD" "Parser"
	__check_prg_exists "$FORMAT_CMD" "Formatter"
}

build_source_file() {
	export SRC="$1"
	export DEST="$2"

	__clog_verbose info "Building " "$SRC"

	local __SRC_EXTENSION="$(get_extension $SRC)"

	local __SRC_FRONTMATTER=$(parse_frontmatter "$SRC")

	[ "$__SRC_EXTENSION" != "sh" ] && local __BODY_RAW=$(parse_body "$SRC")

	set -a

	eval "$__SRC_FRONTMATTER"

	[ "$__SRC_EXTENSION" = "md" ] && BODY=$(__use_parser_prg "$__BODY_RAW")
	[ "$__SRC_EXTENSION" = "html" ] && BODY="$__BODY_RAW"

	set +a

	[ ! -z "$TEMPLATE_FILE" ] &&
		local __TEMPLATE_FILE="$TEMPLATE_FILE" ||
		local __TEMPLATE_FILE=$(__infer_template_file "$SRC" "html")

	local TEMPLATE_FILE_CSS="$(__infer_template_file "$SRC" 'css')"

	[ ! -z "$TEMPLATE_FILE_CSS" ] &&
		local TEMPLATE_FILE_CSS_DEST="$(dirname $DEST)/$(basename $TEMPLATE_FILE_CSS)"

	[ -z "$__TEMPLATE_FILE" ] && __bail "No template file found for $SRC"

	local __TEMPLATE_FRONTMATTER=$(parse_frontmatter "$__TEMPLATE_FILE")

	set -a

	eval "$__TEMPLATE_FRONTMATTER"

	set +a

	local __COMPILED_MD=$(envsubst <<<$(parse_body "$__TEMPLATE_FILE"))

	__clog_verbose info "\tTemplate Chain"
	__clog_verbose info "" "\t$__TEMPLATE_FILE"

	__copy_implicit_template_css "$__TEMPLATE_FILE" "$SRC"

	local __OUT=$(__resolve_template "$__TEMPLATE_FILE" "$__COMPILED_MD" "$SRC")

	[ -z "$__OUT" ] && __bail "Could not build $SRC"

	[ -z "$FORMAT_CMD" ] && echo "$__OUT" >"$DEST"

	[ ! -z "$FORMAT_CMD" ] && echo "$__OUT" | $FORMAT_CMD >"$DEST"

	__clog success "Built " "$SRC --> $DEST"

	unset $(__get_var_names "$__SRC_FRONTMATTER")
	unset $(__get_var_names "$__TEMPLATE_FRONTMATTER")
	unset BODY SRC DIST
}

copy_file() {
	local SRC="$1"
	local DEST="$2"
	if ! cmp -s "$SRC" "$DEST"; then
		[ ! -d "$(dirname $DEST)" ] && mkdir -p "$DEST"
		cp "$SRC" "$DEST" &&
			__clog success "Copied " "$SRC --> $DEST"
	else
		__clog_verbose info "No changes " "$SRC = $DEST"
	fi
}

build_file() {
	(
		local INPUT="$1"

		local OUTPUT="$(infer_out_path $INPUT)"

		local EXTENSION="$(get_extension $INPUT)"

		if [ ! -z "$IGNORE_FILE" ] && [ -f "$IGNORE_FILE" ]; then
			local __IGNORE_FILE_CONTENTS=$(cat "$IGNORE_FILE")
			IFS=$'\n'
			for LINE in $__IGNORE_FILE_CONTENTS; do
				echo "$INPUT" | grep -q "$LINE" && __clog info "Ignoring " "$INPUT" && return 0
			done
			IFS="$DEFAULT_IFS"
		else
			__clog info "Nope"
		fi

		[ ! -d "$(dirname $OUTPUT)" ] && mkdir "$(dirname $OUTPUT)" && __clog success "Created" "$(dirname $OUTPUT)"

		[ "$EXTENSION" = "md" ] && __check_prg_exists "$PARSER_CMD" "Markdown parser "

		if [ "$EXTENSION" = "md" ] || [ "$EXTENSION" = "sh" ] || [ "$EXTENSION" = "html" ]; then
			build_source_file "$INPUT" "$OUTPUT"
		else
			copy_file "$INPUT" "$OUTPUT"
		fi

		return 0
	)
}

build() {

	[ "$CLEAR_BEFORE_BUILD" = true ] && [ "$CLI_QUIET" != true ] && clear && printf '\e[3J' && tput cup 0 0
	[ "$CLI_CLEAN" = true ] && rm -rf "$OUT_DIR/*" && __clog alt "Removed " "$OUT_DIR/*\n"

	__build_preflight

	[ ! -z "$FORMAT_PRG" ] &&
		! command -v $FORMAT_PRG >/dev/null 2>&1 &&
		__bail "Format program $FORMAT_PRG does not exist"

	[ ! -d "$OUT_DIR" ] && mkdir "$OUT_DIR" && __clog success "Created" "$OUT_DIR"

	[ ! -z "$1" ] && build_file "$1" && exit 0

	DEFAULT_IFS="$IFS"

	local HTML_FILES=$(find "$SRC_DIR" -type f -name '*.html')

	local MD_FILES=$(find "$SRC_DIR" -type f -name '*.md')

	local SH_FILES=$(find "$SRC_DIR" -type f -name '*.sh')

	local OTHER_FILES=$(find "$SRC_DIR" -type f -not -name '*.md' -not -name '*.sh' -not -name "*.html")

	__build_list() {
		local __LIST="$1"
		local __LABEL="$2"
		local __PRINT_NEWLINE="$3"

		if [ $(wc -l <<<"$__LIST") -gt 0 ]; then
			__clog_verbose alt "$__LABEL files ($(wc -l <<<$__LIST))"

			for __FILE in $__LIST; do
				build_file "$__FILE"
			done

			[ "$__PRINT_NEWLINE" = true ] && echo
		fi;
	}

	__build_list "$HTML_FILES" "HTML" true

	__build_list "$MD_FILES" "Markdown" true

	__build_list "$SH_FILES" "Sh" true

	__build_list "$OTHER_FILES" "Other"


}

#}}}

#### Init ####{{{

__init_dir() {
	[ -d "$1" ] && __clog info "Exists" "$1"
	[ ! -d "$1" ] && mkdir $1 && __clog success "Created" "$1"
}

init() {
	__init_dir $SRC_DIR
	__init_dir $OUT_DIR
	__init_dir $TEMPLATE_DIR
}

#}}}

#### CLI ####{{{

__usage() {
	cat <<EOF

${0} [OPTIONS] COMMAND

Commands

    init				create SRC_DIR, OUT_DIR, and TEMPLATE_DIR
    serve				run SERVE_CMD
    build				build all files in SRC_DIR
	build-file [FILE]	build FILE

Options
    -h      print this message
    -q      quiet mode - silence output
    -v      verbose mode - print output about all files
    -c      clean mode - remove everything in OUT_DIR before build.
EOF

}

while getopts ":hqcv" opt; do
	case ${opt} in
	h) # process option h
		__usage
		exit 0
		;;
	q)
		readonly CLI_QUIET=true
		;;
	c)
		readonly CLI_CLEAN=true
		;;
	v)
		readonly CLI_VERBOSE=true
		;;
	esac
done

shift "$((OPTIND - 1))"

case "$1" in
"build")
	build
	;;
"build-file")
	[ -z "$2" ] && __bail "Must provide a filename"
	[ ! -f "$2"] && __bail "File $2 does not exist"
	build "$2"
	;;

"init")
	init
	;;
"")
	__usage
	;;
*)
	__clog error "Unknown command" "$1"
	__usage
	;;
esac

#}}}

#### License ####{{{
<<LICENSE

License for markdown.bash 

MIT License

Copyright (c) 2016 Chad Braun-Duin

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

License for shsg.sh

Copyright (c) 2021 Jake Adler

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

LICENSE
#}}}
