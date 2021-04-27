# shsg.sh (shell site generator)

`shsg.sh` is a shell script for generating static websites from markdown.

## [ [Installation](#installation) | [Configuration](#configuration) | [Usage](#usage) | [Credit](#Credit) ]

## Installation

First, create and cd into the directory where you'd like to store your project e.g. `~/my-site/`

```console
mkdir my-site && cd my-site
```

### Install the script 

```console
# wget
wget https://raw.githubusercontent.com/JakeAdler/shsg/master/shsg.sh

# curl
curl -LJO https://raw.githubusercontent.com/JakeAdler/shsg/master/shsg.sh
```

### Give correct permssions

```console
chmod +x ./shsg.sh
```
## Configuration

After installing `shsg.sh`, open it in a text editor and make any necessary changes.

| name              | description                                     | default     | required   |
|-------------------|-------------------------------------------------|-------------|------------|
| `SRC_DIR`         | where source files are located                  | "src"       | yes        |
| `OUT_DIR`         | where output files are located                  | "public"    | yes        |
| `TEMPLATE_DIR`    | where template files are located                | "templates" | yes        |
| `SAFE_BODY`       | markdown body protected or can be overriden     | true        | yes        |
| `QUIET`           | quiet mode                                      | false       | yes        |
| `CACHE_DIR`       | where cached source files will be located       | NONE        | no         |
| `PARSER_CMD`      | command that will parse markdown into html      | NONE        | no         |
| `FORMAT_CMD`      | command that will format outputted html files   | NONE        | no         |
| `SERVE_CMD`       | command that will run on `./shsg.sh serve`      | NONE        | no         |

#### Example configuration

[Pandoc](https://pandoc.org/) with [prettier](https://prettier.io/) and [live-server](https://github.com/tapio/live-server)

```sh
readonly SRC_DIR="src"
readonly OUT_DIR="public"
readonly TEMPLATE_DIR="templates"
readonly SAFE_BODY=true
readonly QUIET=false
readonly CACHE_DIR="$XDG_CACHE_HOME/shsg"
readonly PARSER_CMD="pandoc"
readonly FORMAT_CMD="prettier --parser html"
readonly SERVE_CMD="live-server ./public"
```

## Usage

- [CLI](#cli)
- [Initialization](#initialization)
- [Writing markdown](#writing-markdown)
    - [Frontmatter](#frontmatter)
    - [Markdown syntax caveats](#markdown-syntax-caveats)
- [Other files](#other-files)
- [Using Templates](#using-templates)
    - [Setting template explicitly](#setting-template-explicitly)
    - [Setting template implicitly](#setting-template-implicitly)
    - [Templates and CSS](#templates-and-css)
    - [Template inheritance](#template-inheritance)

## CLI


```
./shsg.sh [COMMAND] [OPTIONS]

Commands

    build   build all files in SRC_DIR --> OUT_DIR
    init    create SRC_DIR, OUT_DIR, and TEMPLATE_DIR
    serve   run SERVE_CMD

Options

    -h      print this message
    -q      quiet mode ( same as setting QUIET=true)
```

## Initialization

Run `./shsg.sh init`, this will simply create the `SRC_DIR`, `OUT_DIR`, and `TEMPLATE_DIR` directories.

Your directory structure should now look like this:

```console
├── public
├── src
├── templates
└── shsg.sh
```

## Writing markdown

`shsg.sh` comes bundled with a stripped down and modified version of [markdown.bash](https://github.com/chadbraunduin/markdown.bash) to parse markdown, however you can [bring your own parser](#example-parser_prg-configurations).

If using the bundled markdown parser, see [caveats](#markdownbash-caveats).

### Frontmatter

Frontmatter in `shsg.sh` is very powerful, since everything between the YAML frontmatter delimiters (`---`) is treated as shell script.

For example:

Source file `src/blog/post-1.md`
```
---
TITLE="My first post"
---

# This is my blog

Some great content
```

Template file `templates/blog.html`
```html
<div>
    <h1>${TITLE}</h1>
    <div>${BODY}</div>
</div>
```

Will produce `public/blog/post-1.html`
```html
<div>
    <h1>My first post</h1>
    <div>
        <h1>This is my blog</h1>
        <p>Some great content</p>
    </div>
</div>
```

There are a few values which can be overriden in frontmatter that will effect how the file gets built:

| Name                | Description                                                       |
|---------------------|-------------------------------------------------------------------|
| `TEMPLATE_FILE`     | Relative path (e.g. `templates/blog.html`) to template HTML file. |
| `TEMPLATE_FILE_CSS` | Relative path (e.g. `templates/blog.css` to template CSS file.    |
| `BODY`              | Body of the markdown file (only if `SAFE_BODY` is false)          |

### [markdown.bash](https://github.com/chadbraunduin/markdown.bash) caveats

#### Multi-line blocks (``` | ~~~)

**Wont work:**
~~~md
Some JavaScript code
```
function add (a, b) {
    return a + b
}
```
~~~

**Will work:**
~~~md
Some JavaScript code
<pre><code>
function add (a, b) {
    return a + b
}
</code></pre>
~~~

#### Nested lists 

**Will work**
```md
- List
- Item
```

**Wont work**

```md
- List
- Item
    - Child

```

**Will work**
```md
<ul>
    <li> List </li>
    <li> Item </li>
    <ul>
        <li> Child </li>
    </ul>
</ul>
```

## Other files

All non-markdown files will be copied to the public directory, including HTML and css files.

## Using templates

Templates are HTML files which contain shell variables, these shell variables will be replaced by [frontmatter](#frontmatter) values, or in some special cases, by values set by `shsg.sh`.

Values set by `shsg.sh`:

| Name   | Description                                |
|--------|--------------------------------------------|
| `BODY` | Where the transpiled HTML will be inserted |

### Setting template explicitly

Templates can be explicitly set using [frontmatter](#frontmatter).

For example, using the following directory structure:

```console
├── public
├── src
│   └── about_me.md
├── templates
│   └── layout.html
└── shsg.sh
```

You can make `src/about_me.md.` use `templates/layout.html` by setting `TEMPLATE_FILE="templates/layout.html"` in the frontmatter of `src/about_me.md`.

`src/about_me.md`
```md
---
TEMPLATE_FILE="templates/layout.html"
---

Lorem ipsum dolor sit amet.
```

### Setting template implicitly

For each file in `TEMPLATE_DIR`, `shsg.sh` will look for a directory with a corresponding directory name, `templates/foo.html` would implicitly be used for all markdown file in `src/foo/*`.

For example, using the following directory structure:

```console
├── public
├── src
│   └── blog
│       └── post-1.md
├── templates
│   └── blog.html
└── shsg.sh
```

All files in `src/blog`, `post-1.md` will have it's template implicitly set to `templates/blog.html`.

#### Implicitly targeting nested directories

Typically, template files will correspond to a directory in `$SRC_DIR/$(basename TEMPLATE_FILE .html)` (e.g. `templates/blog` corresponds to `src/blog`). 

To target a nested directory (e.g `src/blog/special-posts/`), replace directory seperators (`/`) after `SRC_DIR` with underscores `_` (e.g. `templates/blog_special-posts.html`).

### Template inheritance

Templates can be inherit one another by adding the following HTML comment as the **first line** of a template file.

```
<!-- INHERITS path/to/template.html -->
```

The path should be relative from the root project directory, e.g.:

```
<!-- INHERITS templates/parent.html -->

```

When a template inherits another, the `BODY` section of the inherited template is replaced with the inheritee template.

For example:

`templates/html-doc.html`
```html
<html>
    <body>
        ${BODY}
    </body>
<html>
```

`templates/blog.html`
```html
<!-- INHERITS templates/html-doc.html -->
<div>
    <h1>${TITLE}</h1>
    <div>
        ${BODY}
    </div>
<div>
```
Would produce the template
```html
<html>
    <body>
        <div>
            <h1>${TITLE}</h1>
            <div>
                ${BODY}
            </div>
        <div>
    </body>
<html>
```

### Templates and CSS

Template files can have a CSS file with the same basename (e.g. `templates/home.html` and `templates/home.css`) that will be automatically copied once per directory that the template is used. This means that a file which explicitly sets it's template and is not inside the implicit template directory will have the CSS file copied to it's directory.

## Credit

- [chadbraunduin](https://github.com/chadbraunduin) for creating [markdown.bash](https://github.com/chadbraunduin/markdown.bash), which is used in the `parse_md` function.
- [cfenollosa](https://github.com/cfenollosa) for creating [bashblog](https://github.com/cfenollosa/bashblog), which served as an inspiration for this project.
