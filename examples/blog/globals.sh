#!/bin/sh

kebab_case() {
	echo "$1" | sed 's/ /-/g' | tr '[:upper:]' '[:lower:]'
}

print_blog_tags () {
    local __OUT=""

    IFS=":"
    for TAG in $1; do
        __OUT="$__OUT<mark class='tag' data-tag='${TAG}'>${TAG}</mark> "
    done

    echo "$__OUT"
    IFS="$DEFAULT_IFS"
}

export __GO_BACK_HEADER=$(cat <<'EOF'
<header class="go-back-header">
    <a href="/index.html">Home</a>
</header>
EOF
)
