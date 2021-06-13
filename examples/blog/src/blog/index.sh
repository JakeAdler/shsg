HEAD="<link rel='stylesheet' href='__index.css'/>"

BLOG_FILES=$(find "$SRC_DIR/blog" -type f -name "*.md") 

BLOG_LINKS=""

for FILE in $BLOG_FILES; do
    RELATIVE_PATH=$(basename $(infer_out_path "$FILE"))
    __FM=$(parse_frontmatter "$FILE")
    eval "$__FM"

    export BLOG_LINKS=$(cat <<EOF
    ${BLOG_LINKS}
    <div class="blog-link" data-tags='${BLOG_TAGS}'>
        <a href="${RELATIVE_PATH}"><h3>${BLOG_TITLE}</h3></a>
        <p>${BLOG_DATE} $(print_blog_tags "$BLOG_TAGS")</p>
    </div>
EOF
)

    VAR_NAMES=$(__get_var_names "$__FM")
    unset $VAR_NAMES

done

PAGE_TITLE="Blog"

