#!/bin/sh

##################
###  Config    ###
##################

SRC_DIR="src"
OUT_DIR="public"
TEMPLATE_DIR="templates"
FRONTMATTER_TAGS="title|description|date"
FORMAT_PRG="prettier"
FORMAT_PRG_ARGS="--stdin-filepath $TEMPLATE_OUT_PATH --parser html"

##################
### End Config ###
##################

parse_frontmatter () {
    echo -n $(
        sed -n '/---/,/---/p' "$1" |
        sed '1,1d;$d' |
        sed -e 's/:[^:\/\/]/="/g;s/$/"/g;s/ *=/=/g' |
        grep -E "$FRONTMATTER_TAGS" |
        sed 's/.*\[\([^]]*\)].*/\1/'
    )
}


### parse_md {{{
parse_md() {
    OUT="$1"

    IFS='
    '
    refs=$(echo -n "$OUT" | sed -nr "/^\[.+\]: +/p") 
    for ref in $refs
    do
        ref_id=$(echo -n "$ref" | sed -nr "s/^\[(.+)\]: .*/\1/p" | tr -d '\n')
        ref_url=$(echo -n "$ref" | sed -nr "s/^\[.+\]: (.+)/\1/p" | cut -d' ' -f1 | tr -d '\n')
        ref_title=$(echo -n "$ref" | sed -nr "s/^\[.+\]: (.+) \"(.+)\"/\2/p" | sed 's@|@!@g' | tr -d '\n')
        # reference-style image using the label
        OUT=$(echo "$OUT" | sed -r "s|!\[([^]]+)\]\[($ref_id)\]|<img src=\"$ref_url\" title=\"$ref_title\" alt=\"\1\" />|gI")
        # reference-style link using the label
        OUT=$(echo "$OUT" | sed -r "s|\[([^]]+)\]\[($ref_id)\]|<a href=\"$ref_url\" title=\"$ref_title\">\1</a>|gI")
        # implicit reference-style
        OUT=$(echo "$OUT" | sed -r "s|!\[($ref_id)\]\[\]|<img src=\"$ref_url\" title=\"$ref_title\" alt=\"\1\" />|gI")
        # implicit reference-style
        OUT=$(echo "$OUT" | sed -r "s|\[($ref_id)\]\[\]|<a href=\"$ref_url\" title=\"$ref_title\">\1</a>|gI")
    done

    # delete the reference lines
    OUT=$(echo -n "$OUT" | sed -r "/^\[.+\]: +/d")

    # blockquotes
    # use grep to find all the nested blockquotes
    while echo "$OUT" | grep '^> ' >/dev/null
    do
        OUT=$(echo -n "$OUT" | sed -nr '
        /^$/b blockquote
        H
        $ b blockquote
        b
        :blockquote
        x
        s/(\n+)(> .*)/\1<blockquote>\n\2\n<\/blockquote>/ # wrap the tags in a blockquote
        p
        ')

        OUT=$(echo "$OUT" | sed '1 d')

        # cleanup blank lines and remove subsequent blockquote characters
        OUT=$(echo -n "$OUT" | sed -r '
        /^> /s/^> (.*)/\1/
        ')
    done

    # Setext-style headers
    OUT=$(echo -n "$OUT" | sed -nr '
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

    OUT=$(echo "$OUT" | sed '1 d')

    # atx-style headers and other block styles
    OUT=$(echo -n "$OUT" | sed -r '
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
        OUT=$(echo -n "$OUT" | sed -nr '
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

        OUT=$(echo "$OUT" | sed -i '1 d')

        # convert to the proper li to avoid collisions with nested lists
        OUT=$(echo "$OUT" | sed -i 's/uli>/li>/g')

        # prepare any nested lists
        OUT=$(echo "$OUT" | sed -ri '/^[\*\+\-] /s/(.*)/\n\1\n/')
    done

    # ordered lists
    # use grep to find all the nested lists
    while echo "$OUT" | grep -E '^[1-9]+\. ' >/dev/null
    do
        OUT=$(echo -n "$OUT" | sed -nr '
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

        OUT=$(echo -n "$OUT" | sed '1 d' )# cleanup superfluous first line

        # convert list items into proper list items to avoid collisions with nested lists
        OUT=$(echo -n "$OUT" | sed 's/oli>/li>/g')

        # prepare any nested lists
        OUT=$(echo -n "$OUT" | sed -r '/^[1-9]+\. /s/(.*)/\n\1\n/')
    done

    # make escaped periods literal
    OUT=$(echo -n "$OUT" | sed -r '/^[1-9]+\\. /s/([1-9]+)\\. /\1\. /')


    # code blocks
    # OUT=$(echo -n "$OUT" | sed -nr '
    # # if at end of file, append the current line to the hold buffer and print it
    # ${
    # H
    # b code
    # }
    # # wrap the code block on any non code block lines
    # /^\t| {4}/!b code
    # # else, append to the holding buffer and do nothing
    # H
    # b # else, branch to the end of the script
    # :code
    # # exchange the hold space with the pattern space
    # x
    # # look for the code items, if there wrap the pre-code tags
    # /\t| {4}/{
    # s/(\t| {4})(.*)/<pre><code>\n\1\2\n<\/code><\/pre>/ # wrap the ending tags
    # p
    # b
    # }
    # p
    # ')

    OUT=$(echo -n "$OUT" | sed '1 d' )

    # convert html characters inside pre-code tags into printable representations
    OUT=$(echo -n "$OUT" | sed -r '
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
    OUT=$(echo -n "$OUT" | sed -r 's/^\t| {4}(.*)/\1/')

    # br tags
    OUT=$(echo -n "$OUT" | sed -r '
    # if an empty line, append it to the next line, then check on whether there is two in a row
    /^$/ {
    N
    N
    /^\n{2}/s/(.*)/\n<br \/>\1/
    }
    ')

    # emphasis and strong emphasis and strikethrough
    OUT=$(echo -n "$OUT" | sed -nr '
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

    OUT=$(echo -n "$OUT" | sed '1 d' )

    # paragraphs
    OUT=$(echo -n "$OUT" | sed -nr '
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

    OUT=$(echo -n "$OUT" | sed '1 d' )

    # cleanup area where P tags have broken nesting
    OUT=$(echo -n "$OUT" | sed -nr '
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
    OUT=$(echo -n "$OUT" | sed -r '
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

# }}}

FORMAT_CMD=""

[ -z "$FORMAT_PRG" ] && FORMAT_CMD="cat"

[ ! -z "$FORMAT_PRG" ] && [ -z "$FORMAT_PRG_ARGS" ] && FORMAT_CMD="$FORMAT_PRG"

[ ! -z "$FORMAT_PRG" ] && [ ! -z "$FORMAT_PRG_ARGS" ] && FORMAT_CMD="$FORMAT_PRG $FORMAT_PRG_ARGS"


! command -v $FORMAT_PRG > /dev/null 2>&1 && echo "Format program $FORMAT_PRG does not exist"

DEFAULT_IFS=$IFS

[ ! -d $OUT_DIR ] && mkdir $OUT_DIR

for TEMPLATE in "$TEMPLATE_DIR"/*.html
do
    TEMPLATE_BASENAME=$(basename "$TEMPLATE" .html)

    echo "Building \"$TEMPLATE_BASENAME\""

    TEMPLATE_SRC_DIR="$SRC_DIR/$TEMPLATE_BASENAME"
    TEMPLATE_OUT_DIR="$OUT_DIR/$TEMPLATE_BASENAME"

    [ ! -d "$TEMPLATE_OUT_DIR" ] && mkdir "$TEMPLATE_OUT_DIR"

    
    TARGET_FILES=$(find "$TEMPLATE_SRC_DIR" -type f -name "*.md")
    NON_TARGET_FILES=$(find "$TEMPLATE_SRC_DIR" -type f ! -name "*.md")

    for TARGET in $TARGET_FILES
    do
        TARGET_BASENAME=$(basename "$TARGET" .md)
        TEMPLATE_OUT_PATH="$TEMPLATE_OUT_DIR/$TARGET_BASENAME.html"

        eval $(parse_frontmatter "$TARGET")

        IFS='|'

        for FRONTMATTER_VAL in $FRONTMATTER_TAGS
        do
          export "$FRONTMATTER_VAL"
        done

        IFS=$DEFAULT_IFS

        export MD_BODY=$(sed '1 { /^---/ { :a N; /\n---/! ba; d} }' "$TARGET")

        export body=$(parse_md "$MD_BODY")

        envsubst < "$TEMPLATE" | $FORMAT_CMD > "$TEMPLATE_OUT_PATH"

        echo "Built $TARGET --> $TEMPLATE_OUT_PATH"

    done
    
    for NON_TARGET_FILE in $NON_TARGET_FILES
    do
        cp "$NON_TARGET_FILE" "$TEMPLATE_OUT_DIR"
        
        echo "Copied $NON_TARGET_FILES --> $TEMPLATE_OUT_DIR"
    done
done
