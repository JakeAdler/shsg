#!/bin/sh

#### Config ####{{{

# Required
readonly SRC_DIR="src"
readonly OUT_DIR="public"
readonly TEMPLATE_DIR="templates"

# Optional (But recomended)
readonly FORMAT_PRG=""
readonly FORMAT_PRG_ARGS=""

# Optional
readonly LOG_DEFAULT_COLOR="\033[0m"
readonly LOG_ERROR_COLOR="\033[1;31m"
readonly LOG_INFO_COLOR="\033[34m"
readonly LOG_SUCCESS_COLOR="\033[1;32m"
readonly LOG_WARN_COLOR="\033[1;33m"

#}}}

#### Utility functions (internal) ####{{{

__parse_md() {
    local MD_OUT="$1"

    IFS='
    '
    refs=$(echo -n "$OUT" | sed -nr "/^\[.+\]: +/p") 
    for ref in $refs
    do
        ref_id=$(echo -n "$ref" | sed -nr "s/^\[(.+)\]: .*/\1/p" | tr -d '\n')
        ref_url=$(echo -n "$ref" | sed -nr "s/^\[.+\]: (.+)/\1/p" | cut -d' ' -f1 | tr -d '\n')
        ref_title=$(echo -n "$ref" | sed -nr "s/^\[.+\]: (.+) \"(.+)\"/\2/p" | sed 's@|@!@g' | tr -d '\n')
        # reference-style image using the label
        local MD_OUT=$(echo "$OUT" | sed -r "s|!\[([^]]+)\]\[($ref_id)\]|<img src=\"$ref_url\" title=\"$ref_title\" alt=\"\1\" />|gI")
        # reference-style link using the label
        local MD_OUT=$(echo "$OUT" | sed -r "s|\[([^]]+)\]\[($ref_id)\]|<a href=\"$ref_url\" title=\"$ref_title\">\1</a>|gI")
        # implicit reference-style
        local MD_OUT=$(echo "$OUT" | sed -r "s|!\[($ref_id)\]\[\]|<img src=\"$ref_url\" title=\"$ref_title\" alt=\"\1\" />|gI")
        # implicit reference-style
        local MD_OUT=$(echo "$OUT" | sed -r "s|\[($ref_id)\]\[\]|<a href=\"$ref_url\" title=\"$ref_title\">\1</a>|gI")
    done

    # delete the reference lines
    local MD_OUT=$(echo -n "$OUT" | sed -r "/^\[.+\]: +/d")

    # blockquotes
    # use grep to find all the nested blockquotes
    while echo "$OUT" | grep '^> ' >/dev/null
    do
        local MD_OUT=$(echo -n "$OUT" | sed -nr '
        /^$/b blockquote
        H
        $ b blockquote
        b
        :blockquote
        x
        s/(\n+)(> .*)/\1<blockquote>\n\2\n<\/blockquote>/ # wrap the tags in a blockquote
        p
        ')

        local MD_OUT=$(echo "$OUT" | sed '1 d')

        # cleanup blank lines and remove subsequent blockquote characters
        local MD_OUT=$(echo -n "$OUT" | sed -r '
        /^> /s/^> (.*)/\1/
        ')
    done

    # Setext-style headers
    local MD_OUT=$(echo -n "$OUT" | sed -nr '
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

    local MD_OUT=$(echo "$OUT" | sed '1 d')

    # atx-style headers and other block styles
    local MD_OUT=$(echo -n "$OUT" | sed -r '
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
    while echo "$OUT" | grep '^[\*\+\-] ' >/dev/null
    do
        local MD_OUT=$(echo -n "$OUT" | sed -nr '
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

        local MD_OUT=$(echo "$OUT" | sed -i '1 d')

        # convert to the proper li to avoid collisions with nested lists
        local MD_OUT=$(echo "$OUT" | sed -i 's/uli>/li>/g')

        # prepare any nested lists
        local MD_OUT=$(echo "$OUT" | sed -ri '/^[\*\+\-] /s/(.*)/\n\1\n/')
    done

    # ordered lists
    # use grep to find all the nested lists
    while echo "$OUT" | grep -E '^[1-9]+\. ' >/dev/null
    do
        local MD_OUT=$(echo -n "$OUT" | sed -nr '
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

        local MD_OUT=$(echo -n "$OUT" | sed '1 d' )# cleanup superfluous first line

        # convert list items into proper list items to avoid collisions with nested lists
        local MD_OUT=$(echo -n "$OUT" | sed 's/oli>/li>/g')

        # prepare any nested lists
        local MD_OUT=$(echo -n "$OUT" | sed -r '/^[1-9]+\. /s/(.*)/\n\1\n/')
    done

    # make escaped periods literal
    local MD_OUT=$(echo -n "$OUT" | sed -r '/^[1-9]+\\. /s/([1-9]+)\\. /\1\. /')

    # convert html characters inside pre-code tags into printable representations
    local MD_OUT=$(echo -n "$OUT" | sed -r '
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
    local MD_OUT=$(echo -n "$OUT" | sed -r 's/^\t| {4}(.*)/\1/')

    # br tags
    local MD_OUT=$(echo -n "$OUT" | sed -r '
    # if an empty line, append it to the next line, then check on whether there is two in a row
    /^$/ {
    N
    N
    /^\n{2}/s/(.*)/\n<br \/>\1/
    }
    ')

    # emphasis and strong emphasis and strikethrough
    local MD_OUT=$(echo -n "$OUT" | sed -nr '
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

    local MD_OUT=$(echo -n "$OUT" | sed '1 d' )

    # paragraphs
    local MD_OUT=$(echo -n "$OUT" | sed -nr '
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

    local MD_OUT=$(echo -n "$OUT" | sed '1 d' )

    # cleanup area where P tags have broken nesting
    local MD_OUT=$(echo -n "$OUT" | sed -nr '
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
    local MD_OUT=$(echo -n "$OUT" | sed -r '
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

    echo -n "$OUT"
}

__clog () {
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

__bail () {
    __clog error "Error: $1" && exit 1
}

__get_format_cmd () {
    local FORMAT_CMD="cat"

    [ ! -z "$FORMAT_PRG" ] && [ -z "$FORMAT_PRG_ARGS" ] && FORMAT_CMD="$FORMAT_PRG"

    [ ! -z "$FORMAT_PRG" ] && [ ! -z "$FORMAT_PRG_ARGS" ] && FORMAT_CMD="$FORMAT_PRG $FORMAT_PRG_ARGS"

    echo "$FORMAT_CMD"
}

__infer_template_file () {
    local SRC="$1"
    local EXTENSION="$2"

    local SRC_RELATIVE_PATH="${SRC#$SRC_DIR/}"
    local SRC_RELATIVE_DIRNAME=$(dirname "$SRC_RELATIVE_PATH")
    local SRC_RELATIVE_DIRNAME_UNDERSCORED=$(echo "$SRC_RELATIVE_DIRNAME" | sed -e 's/\//_/g')

    echo $(find "$TEMPLATE_DIR" -type f -name "$SRC_RELATIVE_DIRNAME_UNDERSCORED.$EXTENSION")

}

#}}}

#### Utility functions (external) ####{{{

parse_frontmatter () {
    local SRC="$1"

    local FRONTMATTER=$(sed -n '/---/,/---/{/---/b;/---/b;p}' "$SRC")

    echo "$FRONTMATTER"
}

get_extension() {
    local INPUT="$1"
    
    echo "${INPUT##*.}"
}

infer_out_path () {
    local IN_PATH="$1"

    local EXTENSION=$(get_extension "$IN_PATH")

    # Note here "$OUT_DIR" is reffering to the global declared in config.
    local OUT_PATH_DIR="$OUT_DIR$(dirname ${INPUT#$SRC_DIR})"
    local OUT_PATH_FILE="$(basename $IN_PATH $EXTENSION)$([ $EXTENSION = "md" ] && echo 'html' || echo $EXTENSION)"

    local OUT_PATH="$OUT_PATH_DIR/$OUT_PATH_FILE"

    echo "$OUT_PATH"
}

#}}}

#### Build ####{{{

compile_template_file () {

    local SRC="$1"
    local DEST="$2"

    local TEMPLATE_FILE=$(__infer_template_file "$SRC" "html")
    local TEMPLATE_FILE_CSS=$(__infer_template_file "$SRC" "css")

    local TEMPLATE_FILE_CSS_DEST=""

    [ ! -z "$TEMPLATE_FILE_CSS" ] && TEMPLATE_FILE_CSS_DEST="$(dirname $DEST)/$(basename $TEMPLATE_FILE_CSS)"

    local __FRONTMATTER=$(parse_frontmatter "$SRC")
    local __FRONTMATTER_NAMES=$(echo "$__FRONTMATTER" |  grep '=*' | sed 's;=.*;;')

    local MD_BODY=$(sed '1 { /^---/ { :a N; /\n---/! ba; d} }' "$SRC")
    
    set -a

    BODY=$(__parse_md "$MD_BODY")

    eval "$__FRONTMATTER"

    set +a

    # If TEMPLATE_FILE was explicitly set in FRONTMATTER, check if css file exists, if so copy it if not already in dest dir
    [ ! -z "$TEMPLATE_FILE" ] && 
        [ -f "$(dirname $TEMPLATE_FILE)/$(basename $TEMPLATE_FILE .html).css" ]  &&
        TEMPLATE_FILE_CSS="$(dirname $TEMPLATE_FILE)/$(basename $TEMPLATE_FILE .html).css" &&
        TEMPLATE_FILE_CSS_DEST="$(dirname $DEST)/$(basename $TEMPLATE_FILE_CSS)"

    [ -z "$TEMPLATE_FILE" ] && __clog error "Error: " "Template file does not exist for $SRC" && return 1

    [ ! -f "$TEMPLATE_FILE" ] && __clog error "Error: " "Template file $TEMPLATE_FILE does not exist." && return 1

    local FORMAT_CMD="$(__get_format_cmd)"

    envsubst < "$TEMPLATE_FILE" | $FORMAT_CMD > "$DEST"

    unset "$__FRONTMATTER_NAMES"

    __clog success "Built" "$SRC --> $DEST"

    [ ! -z "$TEMPLATE_FILE_CSS" ] && 
        [ -f "$TEMPLATE_FILE_CSS" ] && 
        ! cmp -s "$TEMPLATE_FILE_CSS" "$TEMPLATE_FILE_CSS_DEST" &&
        cat "$TEMPLATE_FILE_CSS" > "$TEMPLATE_FILE_CSS_DEST" &&
        __clog success "Copied" "$TEMPLATE_FILE_CSS --> $TEMPLATE_FILE_CSS_DEST"

}

copy_non_template_file () {

    local SRC="$1" 
    local DEST="$2"

    cp "$SRC" "$DEST" && __clog success "Copied" "$SRC --> $DEST"
}


build_file () {
    local INPUT="$1"

    local OUTPUT=$(infer_out_path "$INPUT")

    local EXTENSION=$(get_extension "$INPUT")

    [ ! -d $(dirname "$OUTPUT") ] && mkdir $(dirname "$OUTPUT") && __clog success "Created" $(dirname "$OUTPUT")

    [ "$EXTENSION" = "md" ] && compile_template_file "$INPUT" "$OUTPUT" && return $?

    [ "$EXTENSION" != "md" ]  && copy_non_template_file "$INPUT" "$OUTPUT" && return $?

}


build () {

    [ ! -z "FORMAT_PRG" ] && 
        ! command -v $FORMAT_PRG > /dev/null 2>&1 && 
        __bail "Format program $FORMAT_PRG does not exist"

    [ ! -d "$OUT_DIR" ] && mkdir "$OUT_DIR" && __clog success "Created" "$OUT_DIR"
    DEFAULT_IFS="$IFS"

    SRC_DIRS=$(find "$SRC_DIR" -not -empty -type d)
    SRC_FILES=$(find "$SRC_DIR" -type f)

    for FILE in $SRC_FILES
    do
        build_file "$FILE"
    done

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
    return 0
}

#}}}

[ -z "$1" ] && build

[ "$1" = "init" ] && init
