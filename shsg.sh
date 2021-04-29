#!/bin/sh

#### Config ####{{{

. "./globals.sh"

# Required
readonly SRC_DIR="src"
readonly OUT_DIR="public"
readonly TEMPLATE_DIR="templates"
readonly SAFE_BODY=true
readonly QUIET=false
readonly CLEAR_BEFORE_BUILD=true

# Optional
readonly CACHE_DIR=""
readonly PARSER_CMD=""
readonly FORMAT_CMD=""
readonly SERVE_CMD="live-server ./public"

# Colors
readonly LOG_DEFAULT_COLOR="\033[0m"
readonly LOG_ERROR_COLOR="\033[1;31m"
readonly LOG_INFO_COLOR="\033[34m"
readonly LOG_SUCCESS_COLOR="\033[1;32m"
readonly LOG_ALT_COLOR="\033[1;35m"
readonly ARROW_DOWN="\t${LOG_INFO_COLOR}↓${LOG_DEFAULT_COLOR}\n\t"

#}}}

#### markdown.bash #####{{{
__parse_md() {
	local MD_OUT="$1"

	IFS=$'\n'

	refs=$(echo -n "$MD_OUT" | sed -nr "/^\[.+\]: +/p")
	for ref in $refs; do
		ref_id=$(echo -n "$ref" | sed -nr "s/^\[(.+)\]: .*/\1/p" | tr -d '\n')
		ref_url=$(echo -n "$ref" | sed -nr "s/^\[.+\]: (.+)/\1/p" | cut -d' ' -f1 | tr -d '\n')
		ref_title=$(echo -n "$ref" | sed -nr "s/^\[.+\]: (.+) \"(.+)\"/\2/p" | sed 's@|@!@g' | tr -d '\n')
		# reference-style image using the label
		local MD_OUT=$(echo "$MD_OUT" | sed -r "s|!\[([^]]+)\]\[($ref_id)\]|<img src=\"$ref_url\" title=\"$ref_title\" alt=\"\1\" />|gI")
		# reference-style link using the label
		local MD_OUT=$(echo "$MD_OUT" | sed -r "s|\[([^]]+)\]\[($ref_id)\]|<a href=\"$ref_url\" title=\"$ref_title\">\1</a>|gI")
		# implicit reference-style
		local MD_OUT=$(echo "$MD_OUT" | sed -r "s|!\[($ref_id)\]\[\]|<img src=\"$ref_url\" title=\"$ref_title\" alt=\"\1\" />|gI")
		# implicit reference-style
		local MD_OUT=$(echo "$MD_OUT" | sed -r "s|\[($ref_id)\]\[\]|<a href=\"$ref_url\" title=\"$ref_title\">\1</a>|gI")
	done

	# delete the reference lines
	local MD_OUT=$(echo -n "$MD_OUT" | sed -r "/^\[.+\]: +/d")

	# blockquotes
	# use grep to find all the nested blockquotes
	while echo "$MD_OUT" | grep '^> ' >/dev/null; do
		local MD_OUT=$(echo -n "$MD_OUT" | sed -nr '
        /^$/b blockquote
        H
        $ b blockquote
        b
        :blockquote
        x
        s/(\n+)(> .*)/\1<blockquote>\n\2\n<\/blockquote>/ # wrap the tags in a blockquote
        p
        ')

		local MD_OUT=$(echo "$MD_OUT" | sed '1 d')

		# cleanup blank lines and remove subsequent blockquote characters
		local MD_OUT=$(echo -n "$MD_OUT" | sed -r '
        /^> /s/^> (.*)/\1/
        ')
	done

	# Setext-style headers
	local MD_OUT=$(echo -n "$MD_OUT" | sed -nr '
    # Setext-style headers need to be wrapped around newlines
    /^$/ b print
    # else, append to holding area
    H
    $ b print
    b
    :print
    x
    /=+$/{
    s/\n(.*)\n=+$/\n<h1>\1<\/h1>/
    p
    b
    }
    /\-+$/{
    s/\n(.*)\n\-+$/\n<h2>\1<\/h2>/
    p
    b
    }
    p
    ')

	local MD_OUT=$(echo "$MD_OUT" | sed '1 d')

	# atx-style headers and other block styles
	local MD_OUT=$(echo -n "$MD_OUT" | sed -r '
    /^#+ /s/ #+$// # kill all ending header characters
    /^# /s/# ([A-Za-z0-9 ]*)(.*)/<h1 id="\1">\1\2<\/h1>/g # H1
    /^#{2} /s/#{2} ([A-Za-z0-9 ]*)(.*)/<h2 id="\1">\1\2<\/h2>/g # H2
    /^#{3} /s/#{3} ([A-Za-z0-9 ]*)(.*)/<h3 id="\1">\1\2<\/h3>/g # H3
    /^#{4} /s/#{4} ([A-Za-z0-9 ]*)(.*)/<h4 id="\1">\1\2<\/h4>/g # H4
    /^#{5} /s/#{5} ([A-Za-z0-9 ]*)(.*)/<h5 id="\1">\1\2<\/h5>/g # H5
    /^#{6} /s/#{6} ([A-Za-z0-9 ]*)(.*)/<h6 id="\1">\1\2<\/h6>/g # H6
    /^\*\*\*+$/s/\*\*\*+/<hr \/>/ # hr with *
    /^---+$/s/---+/<hr \/>/ # hr with -
    /^___+$/s/___+/<hr \/>/ # hr with _
    ')

	# unordered lists
	# use grep to find all the nested lists
	while echo "$MD_OUT" | grep '^[\*\+\-] ' >/dev/null; do
		local MD_OUT=$(echo -n "$MD_OUT" | sed -nr '
        # wrap the list
        /^$/b list
        # wrap the li tags then add to the hold buffer
        # use uli instead of li to avoid collisions when processing nested lists
        /^[\*\+\-] /s/[\*\+\-] (.*)/<\/uli>\n<uli>\n\1/
        H
        $ b list # if at end of file, check for the end of a list
        b # else, branch to the end of the script
        # this is where a list is checked for the pattern
        :list
        # exchange the hold space into the pattern space
        x
        # look for the list items, if there wrap the ul tags
        /<uli>/{
        s/(.*)/\n<ul>\1\n<\/uli>\n<\/ul>/ # close the ul tags
        s/\n<\/uli>// # kill the first superfluous closing tag
        p
        b
        }
        p
        ')

		local MD_OUT=$(echo "$MD_OUT" | sed -i '1 d')

		# convert to the proper li to avoid collisions with nested lists
		local MD_OUT=$(echo "$MD_OUT" | sed -i 's/uli>/li>/g')

		# prepare any nested lists
		local MD_OUT=$(echo "$MD_OUT" | sed -ri '/^[\*\+\-] /s/(.*)/\n\1\n/')
	done

	# ordered lists
	# use grep to find all the nested lists
	while echo "$MD_OUT" | grep -E '^[1-9]+\. ' >/dev/null; do
		local MD_OUT=$(echo -n "$MD_OUT" | sed -nr '
        # wrap the list
        /^$/b list
        # wrap the li tags then add to the hold buffer
        # use oli instead of li to avoid collisions when processing nested lists
        /^[1-9]+\. /s/[1-9]+\. (.*)/<\/oli>\n<oli>\n\1/
        H
        $ b list # if at end of file, check for the end of a list
        b # else, branch to the end of the script
        :list
        # exchange the hold space into the pattern space
        x
        # look for the list items, if there wrap the ol tags
        /<oli>/{
        s/(.*)/\n<ol>\1\n<\/oli>\n<\/ol>/ # close the ol tags
        s/\n<\/oli>// # kill the first superfluous closing tag
        p
        b
        }
        p
        ')

		local MD_OUT=$(echo -n "$MD_OUT" | sed '1 d') # cleanup superfluous first line

		# convert list items into proper list items to avoid collisions with nested lists
		local MD_OUT=$(echo -n "$MD_OUT" | sed 's/oli>/li>/g')

		# prepare any nested lists
		local MD_OUT=$(echo -n "$MD_OUT" | sed -r '/^[1-9]+\. /s/(.*)/\n\1\n/')
	done

	# make escaped periods literal
	local MD_OUT=$(echo -n "$MD_OUT" | sed -r '/^[1-9]+\\. /s/([1-9]+)\\. /\1\. /')

	# convert html characters inside pre-code tags into printable representations
	local MD_OUT=$(echo -n "$MD_OUT" | sed -r '
    # get inside pre-code tags
    /^<pre><code>/{
    :inside
    n
    # if you found the end tags, branch out
    /^<\/code><\/pre>/!{
    s/&/\&amp;/g # ampersand
    s/</\&lt;/g # less than
    s/>/\&gt;/g # greater than
    b inside
    }
    }
    ')

	# remove the first tab (or 4 spaces) from the code lines
	local MD_OUT=$(echo -n "$MD_OUT" | sed -r 's/^\t| {4}(.*)/\1/')

	# br tags
	local MD_OUT=$(echo -n "$MD_OUT" | sed -r '
    # if an empty line, append it to the next line, then check on whether there is two in a row
    /^$/ {
    N
    N
    /^\n{2}/s/(.*)/\n<br \/>\1/
    }
    ')

	# emphasis and strong emphasis and strikethrough
	local MD_OUT=$(echo -n "$MD_OUT" | sed -nr '
    # batch up the entire stream of text until a line break in the action
    /^$/b emphasis
    H
    $ b emphasis
    b
    :emphasis
    x
    s/\*\*(.+)\*\*/<strong>\1<\/strong>/g
    s/__([^_]+)__/<strong>\1<\/strong>/g
    s/\*([^\*]+)\*/<em>\1<\/em>/g
    s/([^\\])_([^_]+)_/\1<em>\2<\/em>/g
    s/\~\~(.+)\~\~/<strike>\1<\/strike>/g
    p
    ')

	local MD_OUT=$(echo -n "$MD_OUT" | sed '1 d')

	# paragraphs
	local MD_OUT=$(echo -n "$MD_OUT" | sed -nr '
    # if an empty line, check the paragraph
    /^$/ b para
    # else append it to the hold buffer
    H
    # at end of file, check paragraph
    $ b para
    # now branch to end of script
    b
    # this is where a paragraph is checked for the pattern
    :para
    # return the entire paragraph into the pattern space
    x
    # look for non block-level elements, if there - print the p tags
    /\n<(div|table|pre|p|[ou]l|h[1-6]|[bh]r|blockquote|li)/!{
    s/(\n+)(.*)/\1<p>\n\2\n<\/p>/
    p
    b
    }
    p
    ')

	local MD_OUT=$(echo -n "$MD_OUT" | sed '1 d')

	# cleanup area where P tags have broken nesting
	local MD_OUT=$(echo -n "$MD_OUT" | sed -nr '
    # if the line looks like like an end tag
    /^<\/(div|table|pre|p|[ou]l|h[1-6]|[bh]r|blockquote)>/{
    h
    # if EOF, print the line
    $ {
    x
    b done
    }
    # fetch the next line and check on whether or not it is a P tag
    n
    /^<\/p>/{
    G
    b done
    }
    # else, append the line to the previous line and print them both
    H
    x
    }
    :done
    p
    ')

	# inline styles and special characters
	local MD_OUT=$(echo -n "$MD_OUT" | sed -r '
    s/<(http[s]?:\/\/.*)>/<a href=\"\1\">\1<\/a>/g # automatic links
    s/<(.*@.*\..*)>/<a href=\"mailto:\1\">\1<\/a>/g # automatic email address links
    # inline code
    s/([^\\])``+ *([^ ]*) *``+/\1<code>\2<\/code>/g
    s/([^\\])`([^`]*)`/\1<code>\2<\/code>/g
    s/!\[(.*)\]\((.*) \"(.*)\"\)/<img alt=\"\1\" src=\"\2\" title=\"\3\" \/>/g # inline image with title
    s/!\[(.*)\]\((.*)\)/<img alt=\"\1\" src=\"\2\" \/>/g # inline image without title
    s/\[(.*)]\((.*) "(.*)"\)/<a href=\"\2\" title=\"\3\">\1<\/a>/g # inline link with title
    s/\[(.*)]\((.*)\)/<a href=\"\2\">\1<\/a>/g # inline link
    # special characters
    /&.+;/!s/&/\&amp;/g # ampersand
    /<[\/a-zA-Z]/!s/</\&lt;/g# less than bracket
    # backslash escapes for literal characters
    s/\\\*/\*/g # asterisk
    s/\\_/_/g # underscore
    s/\\`/`/g # underscore
    s/\\#/#/g # pound or hash
    s/\\\+/\+/g # plus
    s/\\\-/\-/g # minus
    s/\\\\/\\/g # backslash
    ')

	IFS=$DEFAULT_IFS

	local MD_OUT=$(echo -n "$MD_OUT" | sed ':a;N;$!ba;s/>\s*</></g')

	echo -n "$MD_OUT"
}

#}}}

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

    [ "$CLI_QUIET" != true ]  && 
        echo -e ${__COLOR}${2}${LOG_DEFAULT_COLOR}$([ ! -z "$3" ] && echo "$3") > /dev/stderr
}

__clog_verbose() {
	[ "$CLI_VERBOSE" = true ] && __clog "$@"
}

__print_stats () {
	local END_MS=$(date +%s%N | cut -b1-13)

	local TIME_BUILT=$(echo "scale=2; ($END_MS - $START_MS)/1000" | bc -l)

	local __STAT_MESSAGE=""
	[ $__MD_FILES_BUILT -gt 0 ] && __STAT_MESSAGE="${LOG_INFO_COLOR}Built${LOG_DEFAULT_COLOR} $__MD_FILES_BUILT"
	[ $__MD_FILES_NOOP -gt 0 ] && __STAT_MESSAGE="${__STAT_MESSAGE}${LOG_INFO_COLOR}No-op'd${LOG_DEFAULT_COLOR} $__MD_FILES_NOOP"
	__STAT_MESSAGE="$__STAT_MESSAGE ${LOG_ALT_COLOR}markdown${LOG_DEFAULT_COLOR} files\n"
	[ $__OTHER_FILES_BUILT -gt 0 ] && __STAT_MESSAGE="${__STAT_MESSAGE}${LOG_INFO_COLOR}Copied${LOG_DEFAULT_COLOR} ${__OTHER_FILES_BUILT} "
	[ $__OTHER_FILES_NOOP -gt 0 ] && __STAT_MESSAGE="${__STAT_MESSAGE}${LOG_INFO_COLOR}No-op'd${LOG_DEFAULT_COLOR} $__OTHER_FILES_NOOP"
	__STAT_MESSAGE="$__STAT_MESSAGE ${LOG_ALT_COLOR}other${LOG_DEFAULT_COLOR} files"


	__clog_verbose alt "\nStats"

    if [ "$CLI_QUIET" != true ]; then

	    [ "$CLI_VERBOSE" = true ]  && echo -en "$__STAT_MESSAGE" || echo -en "\n$__STAT_MESSAGE"

	    [ "$CLEAR_BEFORE_BUILD" = true ] && [ "$CLI_QUIET" != true ] && tput cup $(tput lines)
    fi


}
 
__bail() {
	__clog error "Error: $1" && exit 1
}

__check_prg_exists() {
	local __PRG="${1%% *}"
	local __LABEL="$2"
	local __REQUIRED="$3"

	__check() {
		! command -v "$1" >/dev/null 2>&1 &&
			__bail "$2 $1 does not exist"
	}

	if [ "$__REQUIRED" = true ]; then
		[ -z "$__PRG" ] && __bail "$__LABEL program is undefined" || __check "$__PRG" "$__LABEL"
	else
		[ ! -z "$__PRG" ] && __check "$__PRG" "$__LABEL"
	fi

}

__use_parser_prg() {
	[ -z "$PARSER_CMD" ] && __parse_md "$1" || echo "$1" | $PARSER_CMD
}

__infer_template_file() {
	local __SRC_FiLE_PATH="$1"
    local __EXTENSION="$2"

    local __RELATIVE_DIRNAME=$(dirname ${__SRC_FiLE_PATH/"$SRC_DIR"\//})

    local __DEEPEST_MATCH=""

    IFS="/"
    for __DIR in $__RELATIVE_DIRNAME; do
        [ -f "$TEMPLATE_DIR/$__DIR.$__EXTENSION" ] && 
            local __DEEPEST_MATCH="$__DEEPEST_MATCH/$__DIR"
    done
    IFS="$DEFAULT_IFS"

    local __INFERED_TEMPLATE_FILE="$TEMPLATE_DIR$__DEEPEST_MATCH.$__EXTENSION"

    [ ! -z "$__INFERED_TEMPLATE_FILE" ] && 
        [ -f "$__INFERED_TEMPLATE_FILE" ] &&
        echo "$__INFERED_TEMPLATE_FILE"
}

__infer_implicit_template_css_path() {
	local __FILE_PATH="$1"

	local __EXTENSION=$(get_extension "$__FILE_PATH")

	local IMPLICIT_CSS="${__FILE_PATH%$__EXTENSION}css"

	[ -f "$IMPLICIT_CSS" ] && echo "$IMPLICIT_CSS"
}

__copy_implicit_template_css() {
	local TEMPLATE="$1"
	local SRC_FILE="$2"

	local IMPLICIT_CSS_SRC=$(__infer_implicit_template_css_path "$TEMPLATE")

	[ -z "$IMPLICIT_CSS_SRC" ] && return 0

	local SRC_FILE_DEST=$(infer_out_path "$SRC_FILE")

	local IMPLICIT_CSS_OUT=$(dirname "$SRC_FILE_DEST")/$(basename "$IMPLICIT_CSS_SRC")

	if ! cmp -s "$IMPLICIT_CSS_SRC" "$IMPLICIT_CSS_OUT"; then
		__OTHER_FILES_BUILT=$((__OTHER_FILES_BUILT + 1))
		cp "$IMPLICIT_CSS_SRC" "$IMPLICIT_CSS_OUT" &&
			__clog_verbose success "\t↪ " "$IMPLICIT_CSS_SRC $LOG_SUCCESS_COLOR(Copied)$LOG_DEFAULT_COLOR"
	else
		__OTHER_FILES_NOOP=$((__OTHER_FILES_NOOP + 1))
        __clog_verbose info "\t↪ " "$IMPLICIT_CSS_SRC $LOG_INFO_COLOR(No changes)$LOG_DEFAULT_COLOR"
	fi
}

__resolve_template() {

	local __SRC_FILE="$1"

	local __ORIGINAL_BODY="$BODY"

	[ -z "$TEMPLATE_FILE" ] && local TEMPLATE_FILE="$(__infer_template_file $__SRC_FILE 'html')"

	local __OUT_BODY=""
	local __INFINITE_RECURSION_COUNTER=0
    local __DID_INFINITE_RECURSE=false

	# If TEMPLATE_FILE was explicitly set in FRONTMATTER, check if corresponding css file exists
	[ ! -z "$TEMPLATE_FILE" ] &&
		[ -f "${TEMPLATE_FILE/.html/.css}" ] &&
		local TEMPLATE_FILE_CSS="${TEMPLATE_FILE/.html/.css}" &&
		local TEMPLATE_FILE_CSS_DEST="$(dirname $__DEST)/$(basename $TEMPLATE_FILE_CSS)"

    # If template was neither explicitly nor implicitly defined, error out.
	[ -z "$TEMPLATE_FILE" ] && __clog error "Error: " "Template file does not exist for $__SRC" && return 1

    # If template file is defined, but does not exist, error out.
	[ ! -f "$TEMPLATE_FILE" ] && __clog error "Error: " "Template file $TEMPLATE_FILE does not exist." && return 1

	__clog_verbose info "\tTemplate chain\n\t" "$TEMPLATE_FILE" 

	__recurse_resolve_template() {
		__INFINITE_RECURSION_COUNTER=$((__INFINITE_RECURSION_COUNTER + 1))

		[ "$__INFINITE_RECURSION_COUNTER" -eq 20 ] && __clog error "\tInfinite recursion detected" && return 1

        local __CHILD_TEMPLATE="$1"
        local __CHILD_TEMPLATE_CONTENTS=$(cat "$__CHILD_TEMPLATE")

	    __copy_implicit_template_css "$__CHILD_TEMPLATE" "$__SRC_FILE"

        local __TEMPLATE_FM=$(parse_frontmatter "$__CHILD_TEMPLATE_CONTENTS"); echo $?

        if [ ! -z "$__TEMPLATE_FM" ]; then
            set -a && eval "$__TEMPLATE_FM" && set +a
            if [ ! -z "$INHERITS" ] && [ -f "$INHERITS" ]; then
                [ "$__CHILD_TEMPLATE" = "$INHERITS" ] && __clog error "\tA template cannot inherit itself" && return 1

                __clog_verbose info '' "$ARROW_DOWN$INHERITS"

                export BODY=$(echo "$__CHILD_TEMPLATE_CONTENTS" | sed '1 { /^<\!\-\-FM/ { :a N; /\-\->/! ba; d} }')

                __OUT_BODY=$(envsubst < "$INHERITS")

                __recurse_resolve_template "$INHERITS"
            else
                __OUT_BODY="$__CHILD_TEMPLATE_CONTENTS"
            fi
        else
            __OUT_BODY="$__CHILD_TEMPLATE_CONTENTS"
        fi 
        
        [ ! -z "$__TEMPLATE_FM" ] && unset $(__get_var_names "$__TEMPLATE_FM")

		export BODY="$__ORIGINAL_BODY"
	}

	__recurse_resolve_template "$TEMPLATE_FILE" && echo "$__OUT_BODY"
}

__get_cache_dir() {
	echo "$CACHE_DIR/${PWD//\//-}"
}

__get_var_names () {
    echo "$1" | grep -i '^[a-z].*=' | sed 's/=.[a-z].*//i'
}

__cache_source_file() {
	local INPUT="$1"
	local OUT="$(__get_cache_dir)/$INPUT"

	[ ! -d "$(dirname $OUT)" ] && mkdir -p "$(dirname $OUT)"

	cp "$INPUT" "$OUT"
}

__check_cache() {
	$([ -z "$CACHE_DIR" ] || [ "$CLI_BYPASS_CACHE" = true ]) && return 1

	local INPUT="$1"
	local CACHE_FILE="$(__get_cache_dir)/$INPUT"

	$([ ! -f "$CACHE_FILE" ] || [ ! -f "$(infer_out_path "$INPUT")" ]) && return 1

	cmp --silent "$INPUT" "$CACHE_FILE"

	return "$?"
}

#}}}

#### Utility functions (external) ####{{{

parse_frontmatter() {

    local __INPUT="$1"

    [ -f "$__INPUT" ] && local __INPUT="$(cat $__INPUT)"

    local __MD_FM=$(echo "$__INPUT" | sed -n '/---/,/---/{/---/b;/---/b;p}')
    [ ! -z "$__MD_FM" ] && echo "$__MD_FM" && return 0
    
    local __HTML_FM=$(echo "$__INPUT" | sed -n '/<\!\-\-FM/,/\-\->/{/<\!\-\-FM/b;/\-\->/b;p}')
    [ ! -z "$__HTML_FM" ] && echo "$__HTML_FM" && return 0

    return 0
}

parse_body () {
    local __INPUT="$1"

    [ -f "$__INPUT" ] && local __INPUT="$(cat $__INPUT)"

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

	if [ ! -z "$CACHE_DIR" ]; then
		[ ! -d "$CACHE_DIR" ] && mkdir "$CACHE_DIR" && __clog success "Created $CACHE_DIR"_

		local THIS_CACHE_DIR="$(__get_cache_dir)"

		[ ! -z "$THIS_CACHE_DIR" ] &&
			[ ! -d "$THIS_CACHE_DIR" ] &&
			mkdir "$THIS_CACHE_DIR" &&
			__clog success "Created $THIS_CACHE_DIR"
	fi
}

__transpile_md_body() {
	local __MD_FILE_SRC="$1"
	local __MD_FILE_DEST="$2"
	local __MD_FILE_FRONTMATTER="$3"

	local __MD_BODY="$(sed '1 { /^---/ { :a N; /\n---/! ba; d} }' $__MD_FILE_SRC)"
	set -a

	$SAFE_BODY = false ] && BODY="$(__use_parser_prg $__MD_BODY)"

	eval "$__FRONTMATTER"

	[ $SAFE_BODY = true ] && BODY="$(__use_parser_prg $__MD_BODY)"

	set +a
}

compile_md_file() {

	local __SRC="$1"
	local __DEST="$2"

    __clog_verbose info "Building " "$__SRC"

    local __SRC_EXTENSION="$(get_extension $__SRC)"

	__check_cache "$__SRC"

	[ "$?" -eq 0 ] && local __CACHED=true || local __CACHED=false

	local TEMPLATE_FILE_CSS="$(__infer_template_file $__SRC 'css')"

	[ ! -z "$TEMPLATE_FILE_CSS" ] &&
		local TEMPLATE_FILE_CSS_DEST="$(dirname $__DEST)/$(basename $TEMPLATE_FILE_CSS)"

	[ "$__SRC_EXTENSION" = "md" ] && local __FRONTMATTER="$(parse_frontmatter $__SRC)"

	local __VAR_NAMES="$(__get_var_names $__FRONTMATTER)"

	[ "$__SRC_EXTENSION" = "md" ] && local __MD_BODY=$(sed '1 { /^---/ { :a N; /\n---/! ba; d} }' "$__SRC")

	set -a

	[ "$__SRC_EXTENSION" = "md" ] && [ "$__CACHED" = false ] && [ "$SAFE_BODY" = false ] && BODY=$(__use_parser_prg "$__MD_BODY")

	[ "$__SRC_EXTENSION" = "md" ] && eval "$__FRONTMATTER"
    [ "$__SRC_EXTENSION" = "sh" ] && eval "$(cat $__SRC)"

	[ "$__SRC_EXTENSION" = "md" ] && [ "$__CACHED" = false ] && [ "$SAFE_BODY" = true ] && BODY=$(__use_parser_prg "$__MD_BODY")

	set +a

    local __TEMPLATE_BODY=$(__resolve_template "$__SRC")

    [ "$?" -eq 1 ] && __clog error "Error: " "error while resolving template for file $__SRC"

    [ "$?" -eq 2 ] && __bail "Circular dependency detected at $TEMPLATE_FILE"


	if [ "$__CACHED" = false ]; then
		[ "$__SRC_EXTENSION" = "md" ] && __MD_FILES_BUILT=$((__MD_FILES_BUILT + 1))

		local __OUT=$(echo "$__TEMPLATE_BODY" | envsubst)

		[ -z "$FORMAT_CMD" ] && echo "$__OUT" > "$__DEST"

		[ ! -z "$FORMAT_CMD" ] && echo "$__OUT" | $FORMAT_CMD > "$__DEST"

		[ ! -z "$__TEMPLATE_CSS_CHAIN" ] && __clog_verbose info "\n\tCSS files\n\t" "$__TEMPLATE_CSS_CHAIN"

		__clog success "Built " "$__SRC --> $__DEST"

	else
		[ "$__SRC_EXTENSION" = "md" ] && __MD_FILES_NOOP=$((__MD_FILES_NOOP + 1))
		__clog info "No changes " "$__SRC"
	fi

	unset "$__VAR_NAMES"
    unset BODY

	[ ! -z "$CACHE_DIR" ] && __cache_source_file "$__SRC"

}

copy_non_md_file() {
	local SRC="$1"
	local DEST="$2"
	if ! cmp -s "$SRC" "$DEST"; then
		__OTHER_FILES_BUILT=$((__OTHER_FILES_BUILT + 1))
		cp "$SRC" "$DEST" &&
			__clog success "Copied" "$SRC --> $DEST"
	else
		__OTHER_FILES_NOOP=$((__OTHER_FILES_NOOP + 1))
		__clog_verbose "info" "No changes " "$SRC = $DEST"
	fi
}

build_file() {

	local INPUT="$1"

	local OUTPUT="$(infer_out_path $INPUT)"

	local EXTENSION="$(get_extension $INPUT)"

	[ ! -d "$(dirname $OUTPUT)" ] && mkdir "$(dirname $OUTPUT)" && __clog success "Created" "$(dirname $OUTPUT)"

	[ "$EXTENSION" = "md" ] && compile_md_file "$INPUT" "$OUTPUT" && return $?

    [ "$EXTENSION" = "sh" ] && compile_md_file "$INPUT" "$OUTPUT" && return $?

	[ "$EXTENSION" != "sh" ] && [ "$EXTENSION" != "md" ] && copy_non_md_file "$INPUT" "$OUTPUT" && return $?

}

build() {

	[ "$CLEAR_BEFORE_BUILD" = true ] && [ "$CLI_QUIET" != true ] && clear && printf '\e[3J' && tput cup 1 0

	__build_preflight

    # Used in __print_stats
	local START_MS="$(date +%s%N | cut -b1-13)"

	[ ! -z "$FORMAT_PRG" ] &&
		! command -v $FORMAT_PRG >/dev/null 2>&1 &&
		__bail "Format program $FORMAT_PRG does not exist"

	[ ! -d "$OUT_DIR" ] && mkdir "$OUT_DIR" && __clog success "Created" "$OUT_DIR"

	DEFAULT_IFS="$IFS"

	local MD_FILES="$(find $SRC_DIR -type f -name '*.md')"

	local SH_FILES="$(find $SRC_DIR -type f -name '*.sh')"

	local OTHER_FILES="$(find $SRC_DIR -type f -not -name '*.md' -not -name '*.sh')"

	local __MD_FILES_BUILT=0
	local __MD_FILES_NOOP=0

	local __OTHER_FILES_BUILT=0
	local __OTHER_FILES_NOOP=0

    __build_list () {
        for __FILE in $1; do
            build_file "$__FILE"
        done
    }

	__clog_verbose alt "Markdown files"

    __build_list "$MD_FILES"

	__clog_verbose alt "\nOther files"

    __build_list "$OTHER_FILES"

	__clog_verbose alt "\nSh files"

    __build_list "$SH_FILES"

    __print_stats

}

#}}}

#### Init ####{{{

init_dir() {
	[ -d "$1" ] && __clog info "Exists" "$1"
	[ ! -d "$1" ] && mkdir $1 && __clog success "Created" "$1"
}

init() {
	init_dir $SRC_DIR
	init_dir $OUT_DIR
	init_dir $TEMPLATE_DIR
}

#}}}

#### Serve ####{{{

__serve_preflight() {
	__check_prg_exists "$SERVE_CMD" "Serve" true
}

serve() {
	__serve_preflight

	__clog "info" "Starting" "serve command '$SERVE_CMD' \n"

	$SERVE_CMD
}

#}}}

#### CLI ####{{{

__usage() {
	cat <<USAGE

${0} [OPTIONS] COMMAND

Commands

    build   build all files in SRC_DIR --> OUT_DIR
    init    create SRC_DIR, OUT_DIR, and TEMPLATE_DIR
    serve   run SERVE_CMD

Options
    -h      print this message
    -q      quiet mode - silence output
    -v      verbose mode - print output about all files
    -c      clean mode - bypasses cache

USAGE

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
		readonly CLI_BYPASS_CACHE=true
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
"init")
	init
	;;
"serve")
	serve
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
