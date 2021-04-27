#!/bin/sh

#### Config ####{{{

# Required
readonly SRC_DIR="src"
readonly OUT_DIR="public"
readonly TEMPLATE_DIR="templates"
readonly SAFE_BODY=true
readonly QUIET=false

# Optional
readonly CACHE_DIR=""

readonly PARSER_CMD=""
readonly FORMAT_CMD=""
readonly SERVE_CMD=""

# Colors
readonly LOG_DEFAULT_COLOR="\033[0m"
readonly LOG_ERROR_COLOR="\033[1;31m"
readonly LOG_INFO_COLOR="\033[34m"
readonly LOG_SUCCESS_COLOR="\033[1;32m"
readonly LOG_WARN_COLOR="\033[1;33m"
readonly ARROW_DOWN="\n\t↓\n\t"

#}}}

#### markdown.bash #####{{{
__parse_md() {
    local MD_OUT="$1"

    IFS='
    '
    refs=$(echo -n "$MD_OUT" | sed -nr "/^\[.+\]: +/p") 
    for ref in $refs
    do
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
    while echo "$MD_OUT" | grep '^> ' >/dev/null
    do
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
    while echo "$MD_OUT" | grep '^[\*\+\-] ' >/dev/null
    do
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
    while echo "$MD_OUT" | grep -E '^[1-9]+\. ' >/dev/null
    do
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

        local MD_OUT=$(echo -n "$MD_OUT" | sed '1 d' )# cleanup superfluous first line

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

    local MD_OUT=$(echo -n "$MD_OUT" | sed '1 d' )

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

    local MD_OUT=$(echo -n "$MD_OUT" | sed '1 d' )

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

__clog () {
    [ "$QUIET" = true ]  && return 0 
    [ "$CLI_QUIET" = true ] && return 0

    local COLOR=""
    case "$1" in
        error)
            COLOR="$LOG_ERROR_COLOR"
            ;;
        info)
            COLOR="$LOG_INFO_COLOR"
            ;;
        success)
            COLOR="$LOG_SUCCESS_COLOR"
            ;;
        warn)
            color="$LOG_WARN_COLOR"
            ;;
    esac

    [ -z "$COLOR" ] && echo "BUG: Invalid color passed to log" && exit 1

    echo -e "${COLOR}${2}${LOG_DEFAULT_COLOR}$([ ! -z "$3" ] && echo " $3")"
}

__clog_verbose () {
    [ "$CLI_VERBOSE" = true ] && __clog "$@"
}

__bail () {
    __clog error "Error: $1" && exit 1
}

__check_prg_exists () {
    local PRG="${1%% *}"
    local LABEL="$2"
    local REQUIRED="$3"

    __check () {
        ! command -v "$1" > /dev/null 2>&1 && 
        __bail "$2 $1 does not exist"
    }

    if [ "$REQUIRED" = true ]; then
        [ -z "$PRG" ] && __bail "$LABEL program is undefined" || __check "$PRG" "$LABEL"
    else
        [ ! -z "$PRG" ] && __check "$PRG" "$LABEL"
    fi

}


__use_parser_prg () {
    local INPUT="$1"

    [ -z "$PARSER_CMD" ] && __parse_md "$INPUT" || echo "$INPUT" | $PARSER_CMD
}

__infer_template_file () {
    local SRC="$1"
    local EXTENSION="$2"

    local SRC_RELATIVE_PATH="${SRC#$SRC_DIR/}"
    local SRC_RELATIVE_DIRNAME=$(dirname "$SRC_RELATIVE_PATH")
    local SRC_RELATIVE_DIRNAME_UNDERSCORED=$(echo "$SRC_RELATIVE_DIRNAME" | sed -e 's/\//_/g')

    echo $(find "$TEMPLATE_DIR" -type f -name "$SRC_RELATIVE_DIRNAME_UNDERSCORED.$EXTENSION")
}

__copy_implicit_template_css () {
    local TEMPLATE="$1"
    local SRC_FILE="$2"

    local SRC_FILE_DEST=$(infer_out_path "$SRC_FILE")

    local IMPLICIT_CSS_SRC="${TEMPLATE%.html}.css"

    local IMPLICIT_CSS_OUT=$(dirname "$SRC_FILE_DEST")/$(basename "$IMPLICIT_CSS_SRC")

    [ -f "$IMPLICIT_CSS_SRC" ] && 
        cp "$IMPLICIT_CSS_SRC" "$IMPLICIT_CSS_OUT" && 
        __clog_verbose info "Copied" "$IMPLICIT_CSS_SRC --> $IMPLICIT_CSS_OUT"
}

__resolve_template () {

    local __TEMPLATE="$1"
    local __SRC_FILE="$2"

    __OUT_BODY=""
    __TEMPLATE_CHAIN="$__TEMPLATE $ARROW_DOWN"
    local __INFINITE_RECURSION_COUNTER=0

    __recurse_resolve_template () {
        local __INFINITE_RECURSION_COUNTER=$((__INFINITE_RECURSION_COUNTER + 1))

        [ "$__INFINITE_RECURSION_COUNTER" -eq 100 ] && return 1

        local INPUT="$1"
        local FIRST_LINE=$(echo "$INPUT" | head -n 1)

        case "$FIRST_LINE" in
            "<!--"*)
                local PARENT=$(echo "$FIRST_LINE" | awk -F '<!-- INHERITS | -->' '{print $2}') 
                if [ -f "$PARENT" ]; then
                    __TEMPLATE_CHAIN="$PARENT $ARROW_DOWN$__TEMPLATE_CHAIN"
                    __copy_implicit_template_css "$PARENT" "$__SRC_FILE"
                    # Set BODY to child template
                    export BODY=$(echo "$INPUT" | tail -n +2)
                    __OUT_BODY="$(envsubst < $PARENT)"
                    __recurse_resolve_template "$__OUT_BODY"
                fi
                ;;
            *)
                __OUT_BODY="$INPUT"
                return 0
        esac
    }

    __copy_implicit_template_css "$__TEMPLATE" "$__SRC_FILE"

    __recurse_resolve_template "$(cat $__TEMPLATE)"

    __TEMPLATE_CHAIN=$(echo -e "$__TEMPLATE_CHAIN" | head -n -2)


    if [ "$?" -eq 0 ]; then
        __TEMPLATE_BODY="$__OUT_BODY"
        return 0
    fi

    [ "$?" -eq 1 ] && return 1

}

__get_cache_dir () {
    echo "$CACHE_DIR/${PWD//\//-}"
}

__cache_source_file () {
    local INPUT="$1"
    local OUT="$(__get_cache_dir)/$INPUT"

    [ ! -d $(dirname "$OUT") ] && mkdir -p $(dirname "$OUT")

    cp "$INPUT" "$OUT"
}

__check_cache () {
    $([ -z "$CACHE_DIR" ] || [ "$CLI_BYPASS_CACHE" = true ]) && return 1

    local INPUT="$1"
    local CACHE_FILE="$(__get_cache_dir)/$INPUT"

    $([ ! -f "$CACHE_FILE" ] || [ ! -f $(infer_out_path "$INPUT") ]) && echo "2" && return 1

    cmp --silent "$INPUT" "$CACHE_FILE"

    return "$?"
}


#}}}

#### Utility functions (external) ####{{{

parse_frontmatter () {
    sed -n '/---/,/---/{/---/b;/---/b;p}' "$1"
}

get_extension() {
    echo "${1##*.}"
}

infer_out_path () {
    local IN_PATH="$1"

    local EXTENSION=$(get_extension "$IN_PATH")

    local OUT_EXTENSION=""
    [ "$EXTENSION" = "md" ] && OUT_EXTENSION="html" || OUT_EXTENSION="$EXTENSION"
    # Note here "$OUT_DIR" is reffering to the global declared in config.
    local OUT_PATH_DIR=$(dirname "${IN_PATH/$SRC_DIR/$OUT_DIR}")
    local OUT_PATH_FILE="$(basename $IN_PATH $EXTENSION)$OUT_EXTENSION"

    local OUT_PATH="$OUT_PATH_DIR/$OUT_PATH_FILE"

    echo "$OUT_PATH"
}

#}}}

#### Build ####{{{

__build_preflight () {
    __check_prg_exists "$PARSER_CMD" "Parser"
    __check_prg_exists "$FORMAT_CMD" "Formatter"

    if [ ! -z "$CACHE_DIR" ]; then
        [ ! -d "$CACHE_DIR" ] && mkdir "$CACHE_DIR" && __clog success "Created $CACHE_DIR"_

        local THIS_CACHE_DIR=$(__get_cache_dir)

        [ ! -z "$THIS_CACHE_DIR" ] && 
            [ ! -d "$THIS_CACHE_DIR" ] && 
            mkdir "$THIS_CACHE_DIR" && 
            __clog success "Created $THIS_CACHE_DIR"
    fi

}

compile_md_file () {

    local __SRC="$1"
    local __DEST="$2"

    __check_cache "$__SRC"

    [ "$?" -eq 0 ] && local __CACHED=true || local __CACHED=false

    local TEMPLATE_FILE=$(__infer_template_file "$__SRC" "html")
    local TEMPLATE_FILE_CSS=$(__infer_template_file "$__SRC" "css")

    [ ! -z "$TEMPLATE_FILE_CSS" ] && 
        local TEMPLATE_FILE_CSS_DEST="$(dirname $__DEST)/$(basename $TEMPLATE_FILE_CSS)"

    local __FRONTMATTER=$(parse_frontmatter "$__SRC")
    local __FRONTMATTER_NAMES=$(echo "$__FRONTMATTER" |  grep '=*' | sed 's;=.*;;')

    local __MD_BODY=$(sed '1 { /^---/ { :a N; /\n---/! ba; d} }' "$__SRC")
    
    set -a

    [ "$__CACHED" = false ] && [ $SAFE_BODY = false ] && BODY=$(__use_parser_prg "$__MD_BODY")

    eval "$__FRONTMATTER"

    [ "$__CACHED" = false ] && [ $SAFE_BODY = true ] && BODY=$(__use_parser_prg "$__MD_BODY")

    set +a


    # If TEMPLATE_FILE was explicitly set in FRONTMATTER, check if css file exists, if so copy it if not already in dest dir
    [ ! -z "$TEMPLATE_FILE" ] && 
        [ -f "$(dirname $TEMPLATE_FILE)/$(basename $TEMPLATE_FILE .html).css" ]  &&
        local TEMPLATE_FILE_CSS="$(dirname $TEMPLATE_FILE)/$(basename $TEMPLATE_FILE .html).css" &&
        local TEMPLATE_FILE_CSS_DEST="$(dirname $__DEST)/$(basename $TEMPLATE_FILE_CSS)"

    [ -z "$TEMPLATE_FILE" ] && __clog error "Error: " "Template file does not exist for $__SRC" && return 1

    [ ! -f "$TEMPLATE_FILE" ] && __clog error "Error: " "Template file $TEMPLATE_FILE does not exist." && return 1

    __TEMPLATE_BODY=""

    __resolve_template "$TEMPLATE_FILE" "$__SRC" || __bail "Circular dependency detected at $TEMPLATE_FILE"

    if [ "$__CACHED" = false ]; then

        local __OUT=$(echo "$__TEMPLATE_BODY" | envsubst)

        [ -z "$FORMAT_CMD" ] && echo "$__OUT" > "$__DEST" 

        [ ! -z "$FORMAT_CMD" ] &&  echo "$__OUT" | $FORMAT_CMD > "$__DEST" 
        
        __clog success "Built" "$__SRC --> $__DEST"

        __clog_verbose info "\tTemplate chain\n       " "$__TEMPLATE_CHAIN"


    else
        __clog info "No changes" "$__SRC"
    fi

    unset "$__FRONTMATTER_NAMES"

    [ ! -z "$CACHE_DIR" ] &&  __cache_source_file "$__SRC"

    [ ! -z "$TEMPLATE_FILE_CSS" ] && copy_non_md_file "$TEMPLATE_FILE_CSS" "$TEMPLATE_FILE_CSS_DEST"

}

copy_non_md_file () {
    local SRC="$1" 
    local DEST="$2"
    if [ -f "$DEST" ]; then
        if ! cmp -s "$SRC" "$DEST"; then
            cp "$SRC" "$DEST" &&
                __clog success "Copied" "$SRC --> $DEST"
        else
            __clog_verbose "info" "Same file" "$SRC = $DEST"
        fi
    fi
}


build_file () {

    local INPUT="$1"

    local OUTPUT=$(infer_out_path "$INPUT")

    local EXTENSION=$(get_extension "$INPUT")

    [ ! -d $(dirname "$OUTPUT") ] && mkdir $(dirname "$OUTPUT") && __clog success "Created" $(dirname "$OUTPUT")

    [ "$EXTENSION" = "md" ] && compile_md_file "$INPUT" "$OUTPUT" && return $?

    [ "$EXTENSION" != "md" ]  && copy_non_md_file "$INPUT" "$OUTPUT" && return $?

}


build () {

    __build_preflight

    local START_MS=$(date +%s%N | cut -b1-13)

    [ ! -z "$FORMAT_PRG" ] && 
        ! command -v $FORMAT_PRG > /dev/null 2>&1 && 
        __bail "Format program $FORMAT_PRG does not exist"

    [ ! -d "$OUT_DIR" ] && mkdir "$OUT_DIR" && __clog success "Created" "$OUT_DIR"

    DEFAULT_IFS="$IFS"

    local SRC_FILES=$(find "$SRC_DIR" -type f)

    for FILE in $SRC_FILES
    do
        build_file "$FILE"
    done

    local END_MS=$(date +%s%N | cut -b1-13)

    local TIME_BUILT=$(echo "scale=2; ($END_MS - $START_MS)/1000" | bc -l)

    local MD_FILES=$(find "$SRC_DIR" -type f -name "*.md" | wc -l)

    local OTHER_FILES=$(find "$SRC_DIR" -type f -not -name "*.md" | wc -l)

    __clog info "\nBuilt" "$MD_FILES markdown files and copied $OTHER_FILES other files in ${TIME_BUILT}s"

}

#}}}

#### Init ####{{{

init_dir () {
    [ -d "$1" ] && __clog info "Exists" "$1"
    [ ! -d "$1" ] && mkdir $1 && __clog success "Created" "$1" 
}

init () {
    init_dir $SRC_DIR
    init_dir $OUT_DIR
    init_dir $TEMPLATE_DIR
}

#}}}

#### Serve ####{{{

__serve_preflight () {
    __check_prg_exists "$SERVE_CMD" "Serve" true
}

serve () {
    __serve_preflight

    __clog "info" "Starting" "serve command '$SERVE_CMD' \n"

    $SERVE_CMD
}

#}}}

#### CLI ####{{{

__usage () {
    cat << USAGE

${0} [OPTIONS] COMMAND

Commands

    build   build all files in SRC_DIR --> OUT_DIR
    init    create SRC_DIR, OUT_DIR, and TEMPLATE_DIR
    serve   run SERVE_CMD

Options

    -h      print this message
    -q      quiet mode ( same as setting QUIET=true)
    -c      clean mode - bypasses cache

USAGE

}

while getopts ":hqcv" opt; do
  case ${opt} in
    h ) # process option h
        __usage
        exit 0
        ;;
    q )
        readonly CLI_QUIET=true
        ;;
    c )
        readonly CLI_BYPASS_CACHE=true
        ;;
    v )
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
